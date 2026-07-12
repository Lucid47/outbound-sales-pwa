# Group SMS 제품화 및 적용 액션플랜

작성일: 2026-07-13

## 문서 목적

이 문서는 두 가지 목표를 동시에 만족시키기 위한 실행 기준이다.

1. 현재 `소희가 간다`에 고객관리 데이터와 연결된 단체문자 기능을 완성한다.
2. 검증된 기능을 나중에 별도의 유료 단체문자 앱으로 분리해 배포할 수 있게 한다.

경쟁 앱 조사와 세부 근거는 `docs/group-sms-competitor-research.md`, 공통 알고리즘과 Android 포팅 기준은 `docs/group-sms-implementation-guide.md`, 실제 발송 시험은 `docs/group-sms-test-plan.md`를 따른다.

## 결론

현재 단계에서 별도 저장소나 별도 앱 타깃을 바로 만들지는 않는다. 먼저 Group SMS를 제품 중립적인 Swift Package와 `소희가 간다` 전용 어댑터로 분리하고, 실기기 검증이 끝난 뒤 독립 앱 저장소 또는 앱 타깃으로 옮긴다.

이 접근의 장점:

- 같은 발송 엔진을 두 앱에서 재사용할 수 있다.
- CRM 전용 고객·스케줄·지도 기능이 독립 메시징 앱에 섞이지 않는다.
- 단축어명, callback scheme, 앱 아이콘과 과금을 제품별로 교체할 수 있다.
- Android는 동일한 JSON Schema와 테스트 벡터를 사용해 별도 구현할 수 있다.

## 목표 아키텍처

```text
GroupMessagingCore
  - 전화번호 정규화
  - 중복/제외 처리
  - 템플릿 치환
  - 캠페인/수신자 상태 머신
  - 지연·묶음 계획
  - 정책 보호선
  - 사전점검 결과
  - JSON payload와 테스트 벡터

GroupMessagingTransportIOS
  - Shortcuts 실행 설정
  - callback 해석
  - 단축어 버전/준비 상태
  - 첨부파일 전달 어댑터

SoheeGroupMessagingAdapter
  - Customer -> MessageTarget 변환
  - 고객리스트/오늘 스케줄/필터 결과 제공
  - 고객 히스토리 기록
  - Google Drive 백업 데이터 연결

StandaloneMessagingApp
  - iOS 연락처/CSV/수동 그룹
  - 독립 템플릿과 캠페인 기록
  - StoreKit 구독/무료 시험
  - 독립 개인정보 처리방침과 온보딩
```

## 지금 코드에서 분리해야 할 결합 지점

### 제품 설정

현재 `GroupSmsBuilder`에 다음 값이 고정되어 있다.

- 단축어명 `SoheeGroupSMS`
- callback scheme `com.lucid47.outboundsales`
- 단축어 버전
- callback 경로

이를 `GroupSmsTransportConfiguration`으로 옮긴다.

```swift
public struct GroupSmsTransportConfiguration: Sendable {
    public let shortcutName: String
    public let shortcutVersion: String
    public let callbackScheme: String
    public let successPath: String
    public let cancelPath: String
    public let errorPath: String
}
```

`소희가 간다`와 독립 앱은 서로 다른 설정 인스턴스를 주입한다. 독립 앱은 별도 Bundle ID, URL scheme, 단축어 이름을 사용한다.

### 수신자 원본

현재 빌더는 `Customer`를 직접 입력받고 캠페인은 `customerListId`를 보관한다. 공통 엔진에서는 다음 제품 중립 타입을 사용한다.

```swift
public struct GroupMessageTarget: Sendable {
    public let sourceRecordId: String?
    public let displayName: String
    public let phoneNumber: String
    public let mergeFields: [String: String]
    public let sourceMetadata: [String: String]
}
```

- `소희가 간다`: `Customer`를 `GroupMessageTarget`으로 변환
- 독립 앱: iOS 연락처, CSV 행, 수동 입력을 같은 타입으로 변환
- `customerListId`는 공통 캠페인 필드가 아니라 CRM 어댑터의 metadata로 저장

### 저장소

공통 UI와 엔진은 `NativeAppState`에 직접 의존하지 않고 아래 프로토콜을 사용한다.

```swift
public protocol GroupSmsCampaignRepository {
    func save(_ campaign: GroupSmsCampaign) async throws
    func campaign(id: String) async throws -> GroupSmsCampaign?
    func recentCampaigns(limit: Int) async throws -> [GroupSmsCampaign]
}
```

`소희가 간다`는 기존 JSON/Drive 저장 어댑터, 독립 앱은 별도 SwiftData 또는 파일 저장 어댑터를 구현할 수 있다.

### UI

현재 `GroupSmsTestView`는 설치, 대상, 작성, 지연, 보호선, 실행, 기록을 하나의 긴 `Form`에 담는다. 검증용 화면으로는 유효하지만 제품 화면으로 유지하지 않는다.

제품 UI는 다음 6단계 상태와 화면으로 분리한다.

1. 자동화 준비
2. 대상 선택
3. 메시지 작성
4. 발송 전 점검
5. 발송 진행
6. 결과와 복구

테스트 모드는 설정의 `개발 및 진단` 하위로 이동하고 실제 고객 캠페인 화면과 분리한다.

## 상태 모델 보강

### 자동화 준비 상태

```text
notInstalled
installedNeedsTest
messagePermissionRequired
attachmentPermissionRequired
ready
updateRequired
unavailable
```

단순 `shortcutVerified: Bool` 대신 상태와 마지막 시험일, 시험한 단축어 버전을 저장한다.

### 캠페인 상태

```text
draft -> validating -> ready -> launching -> running
running -> requestCompleted
running -> cancelled
running -> failed
running -> interrupted
```

### 수신자 상태

```text
pending
excluded
requesting
requested
failed
unknown
```

iOS Shortcuts가 대상별 진행 상황을 앱에 전달하지 못하는 1차 버전에서는 캠페인 완료 callback 이전의 수신자를 임의로 `requested`로 바꾸지 않는다. 중단 시 처리 여부를 확인할 수 없는 수신자는 `unknown`으로 저장한다.

## 소희가 간다 적용 액션플랜

### 단계 0: 기준선 고정

목표: 현재 실기기에서 성공한 텍스트 반복 발송을 회귀 기준으로 보존한다.

작업:

- 현재 payload와 단축어 동작을 golden fixture로 저장
- 본인 번호 2~3개 반복 시험 결과를 테스트 문서에 고정
- 현재 `GroupSmsTestView`는 제품 화면 완성 전까지 진단 화면으로 유지
- 실제 전화번호와 수신 화면은 Git에서 제외

완료 조건:

- 기존 Core 테스트 통과
- 실기기 텍스트 자동 반복 발송 재확인

### 단계 1: 공통 코어 분리

목표: CRM 모델 없이 캠페인을 만들 수 있게 한다.

작업:

- `GroupMessageTarget` 도입
- `Customer -> GroupMessageTarget` 어댑터 구현
- `GroupSmsTransportConfiguration` 도입
- 단축어명과 callback scheme 하드코딩 제거
- 캠페인/수신자 상태 확장
- 제외 사유 모델 추가
  - 전화번호 없음
  - 잘못된 전화번호
  - 중복 번호
  - 사용자 제외
  - 최근 발송 제외
- JSON Schema 버전 증가와 이전 백업 마이그레이션

완료 조건:

- Customer 없이 생성한 테스트 대상 캠페인과 Customer 캠페인이 같은 payload 규칙을 사용
- 기존 백업 데이터가 마이그레이션 후 열림
- callback URL이 주입된 제품 설정으로 생성됨

### 단계 2: 자동화 준비 화면

목표: 사용자가 단축어 사용 가능 여부를 한 화면에서 판단하게 한다.

화면:

- 상태 카드
- 필요한 단축어 이름과 버전
- `단축어 설치`
- `설치 확인`
- `텍스트 시험`
- `첨부 시험`
- `업데이트`
- 마지막 시험일

구현 주의:

- 앱이 단축어를 조용히 설치했다고 표현하지 않는다.
- URL을 열었다는 사실과 실제 설치·권한 성공을 구분한다.
- 첨부 권한 상태는 텍스트 권한과 분리한다.

완료 조건:

- 미설치, 시험 필요, 준비 완료, 업데이트 필요 UI를 강제로 재현하는 단위/UI 테스트
- 새 iPhone에서 안내만 보고 단축어 준비 완료

### 단계 3: 대상 선택과 메시지 작성

목표: 기존 고객관리 맥락에서 3단계 캠페인을 만든다.

진입점:

- 고객리스트 카드의 `단체문자`
- 고객 다중 선택 도구막대
- 오늘 스케줄 선택 결과
- 현재 검색/필터 결과

대상 화면:

- 대상 체크박스와 전체 선택
- 유효 대상, 중복, 잘못된 번호, 전화번호 없음 수
- 제외 사유별 목록
- 최근 발송 대상 제외 옵션

작성 화면:

- 기존 문자 템플릿
- 본문과 개인화 필드
- 사진 1장 또는 파일 1개
- 대상별 미리보기
- 특정 대상의 최종 문구만 수정
- 고정/랜덤 간격과 묶음 휴식
- 초안 저장

완료 조건:

- 서로 다른 세 진입점이 동일한 캠페인 편집 흐름으로 연결
- 중복 번호가 기본 1회만 포함
- 모든 대상의 치환 결과를 발송 전에 확인 가능

### 단계 4: 발송 전 점검

목표: 잘못된 대량 발송을 시작 전에 차단한다.

표시 항목:

- 전체 후보, 유효 대상, 제외 대상
- SMS/LMS/MMS 예상 분류
- 첨부 종류와 크기
- 예상 소요시간
- 오늘·이번 달 발송 요청 누적
- 정책 보호선 경고
- 빈 개인화 값
- 단축어/권한/버전 상태
- 테스트 번호 포함 여부

차단 조건:

- 유효 대상 0명
- 빈 메시지와 첨부 모두 없음
- 단축어 준비 안 됨
- 일 최대 제한 초과
- 지원하지 않는 첨부 형식 또는 용량

완료 조건:

- 위험 조건별 발송 버튼 비활성화 테스트
- 사용자가 제외 사유와 수정 위치를 바로 찾을 수 있음

### 단계 5: 발송 진행

목표: 확인 가능한 상태만 정직하게 표시하고 중단 경로를 제공한다.

1차 표시:

- 캠페인명과 전체 대상 수
- Shortcuts 실행 여부
- 경과시간과 예상 남은 시간
- 사용자가 중단하는 방법
- `발송 요청 진행 중` 문구

중요한 제약:

- 캠페인 단위 callback만으로는 현재 고객과 정확한 완료 수를 실시간으로 알 수 없다.
- 따라서 1차 화면에서 `현재 고객`, `정확한 완료 수`를 실제 값처럼 표시하지 않는다.
- 대상별 진행 callback을 제공하는 App Intent 또는 다른 bridge가 실기기에서 검증된 뒤 2차로 활성화한다.
- 앱의 중단 버튼이 실행 중인 단축어를 실제로 정지시키는지는 별도 실기기 Gate를 통과해야 한다. 검증 전에는 Shortcuts에서 중단하는 안내와 앱의 캠페인 취소 기록을 분리한다.

2차 진행 프로토콜 후보:

```text
willRequest(recipientId, order)
didRequest(recipientId, order)
didFail(recipientId, reason)
campaignFinished(campaignId)
```

완료 조건:

- 앱 전환, 잠금, 전화 수신, Shortcuts 중단 시 상태가 과장되지 않음
- callback 부재 시 캠페인이 자동 완료 처리되지 않음

### 단계 6: 결과와 안전 복구

목표: 중복 문자 없이 남은 대상을 다시 처리한다.

결과 그룹:

- 요청 완료
- 요청 전
- 상태 미확정
- 제외
- 오류

복구 규칙:

- `요청 전`만 기본 재발송 대상으로 선택
- `상태 미확정`은 기본 선택 해제
- 사용자가 미확정 목록을 확인한 뒤 명시적으로 포함
- 원 캠페인 ID와 재시도 캠페인 ID를 연결
- callback 완료는 `전달 완료`가 아니라 `발송 요청 완료`로 기록

완료 조건:

- 중간 중단 시험에서 전체 자동 재발송이 발생하지 않음
- 고객 히스토리에 원 캠페인과 재시도 캠페인이 구분됨

### 단계 7: 첨부파일

목표: 사진 1장부터 안정적으로 발송한다.

순서:

1. 사진 1장
2. 파일 1개
3. 다중 첨부

작업:

- 앱 저장소에 캠페인 첨부 복사
- 파일 유형, 크기, 존재 여부 사전검사
- Shortcuts에서 읽을 수 있는 App Intent 또는 임시 파일 전달 구현
- 첨부 권한 전용 시험
- 성공·취소·만료 시 임시 파일 정리
- 백업 포함 여부와 보관기간 설정

완료 조건:

- 텍스트+사진, 사진만 발송 시험
- 앱 재실행과 중단 후 임시 파일 누수 없음

### 단계 8: 제품화 준비

`소희가 간다` 통합 기능이 아래 조건을 만족하면 독립 앱 작업을 시작한다.

- 텍스트 캠페인 20회 이상 회귀 시험
- 중단/미확정/재시도 시험 통과
- 첨부 1장 시험 통과
- 새 기기 설치 온보딩 시험 통과
- Core가 `Customer`, `NativeAppState`, CRM 화면에 의존하지 않음
- JSON Schema와 테스트 벡터 고정

독립 앱에서 새로 구현할 항목:

- 별도 Bundle ID와 URL scheme
- 별도 단축어 이름과 배포 링크
- 독립 연락처/CSV/그룹 저장소
- StoreKit 무료 시험과 구독
- App Store 개인정보 표시와 이용약관
- 독립 앱 아이콘, 이름, 온보딩과 지원 채널
- CRM 기능을 제외한 캠페인/템플릿/기록 중심 탭 구조

## 권장 작업 단위

| 작업 묶음 | 주요 산출물 | 실기기 Gate |
| --- | --- | --- |
| A. 코어 분리 | 제품 중립 모델, 설정 주입, 마이그레이션 | 기존 텍스트 발송 회귀 |
| B. 준비 상태 | 설치·버전·권한 상태 화면 | 새 기기 온보딩 |
| C. 작성 흐름 | 대상, 작성, 미리보기, 초안 | 본인 번호 캠페인 |
| D. 사전점검 | 제외 사유, 한도, 예상시간 | 차단 조건 확인 |
| E. 진행·복구 | 상태 모델, 중단, 미확정 재개 | 중간 중단 반복 |
| F. 첨부 | 사진 1장, 권한, 임시파일 | 사진 실제 수신 |
| G. 독립 앱 | 별도 타깃/저장소/과금 | TestFlight 파일럿 |

각 묶음은 구현, 자동 테스트, 본인 번호 실기기 시험, 문서 갱신까지 완료해야 다음 단계로 이동한다.

## 이번 범위에서 확정하지 않는 것

- 통신사 최종 전달 성공 판정
- 사용자 모르게 실행되는 백그라운드 SMS 발송
- iOS 단축어의 완전한 블랙박스화
- 대량 마케팅 발송을 위한 제한 우회
- 500명 이상 규모를 Shortcuts 방식으로 보장

이 항목이 필요해지면 서버 SMS 또는 Android 기본 SMS 앱 역할을 별도 제품 옵션으로 검토한다.
