# Group SMS 개발 검토 및 구현 계획

## 목적

`소희가 간다` 네이티브 앱에서 선택한 고객들에게 단톡방을 만들지 않고 1:1 개별 문자처럼 순차 발송하는 기능을 개발한다.

이 기능은 기존 고객관리 흐름과 결합되어야 한다.

- 고객리스트 또는 필터 결과에서 여러 고객 선택
- 문자 템플릿 작성 및 개인화 치환
- 단톡방 생성 없이 개별 발송
- 발송 요청 이력과 대상별 로그 저장
- 기존 고객 히스토리와 기록 탭에서 조회

## 조사 문서 요약

검토한 문서:

- `/Users/daehee/Downloads/아이폰 단체문자 앱 개발 검토.pdf`
- `/Users/daehee/Downloads/지금까지 조사한 내용을 바탕으로 아이폰에서 해당 기능을 개발하기 위해 고려해야할 사항을....pdf`
- `/Users/daehee/Downloads/기존 고객관리 앱 통합을 위한 단체문자 솔루션(서드파티 앱 vs 직접 개발) 비용 및 사용성 비교 분석.pdf`

핵심 결론:

1. iOS 네이티브 `MFMessageComposeViewController`만으로는 사용자의 물리적 전송 탭 없이 SMS/MMS/iMessage를 자동 발송할 수 없다.
2. `MFMessageComposeViewController`에 여러 수신자를 넣으면 단톡방 또는 그룹 MMS/iMessage가 만들어질 수 있으므로 요구사항과 맞지 않는다.
3. 완전한 개별 순차 발송에 가까운 현실적 방법은 iOS Shortcuts 앱과 URL Scheme/x-callback-url을 연동하는 구조다.
4. Quick Send, Reach, BCC Text 등 상용 앱도 Shortcuts 기반 자동화 또는 유사한 우회 구조를 핵심으로 삼는다.
5. 상용 앱 도입은 빠르지만 기존 고객관리 앱의 데이터, 이력, 템플릿, 고객 상태와 깊게 통합하기 어렵다.
6. 자체 구현은 초기 개발비가 들지만 기존 CRM 데이터와 완전히 결합할 수 있고, 별도 서버 문자 비용 없이 사용자의 iPhone 문자 요금제를 활용할 수 있다.

## iOS 제약사항

### 네이티브 문자 작성 화면

Apple MessageUI의 `MFMessageComposeViewController`는 표준 문자 작성 화면을 제공한다. 앱은 수신자와 본문을 미리 채울 수 있지만, 실제 전송은 사용자가 화면에서 직접 눌러야 한다.

따라서 다음은 불가능하다.

- 앱 내부에서 SMS를 조용히 자동 발송
- 사용자의 전송 탭 없이 백그라운드 일괄 발송
- 여러 명에게 넣고도 단톡방 없이 MessageUI 하나로 자동 개별 발송

현재 앱의 단일 고객 문자 기능은 이 제약 안에서 정상적인 방식이다.

### Shortcuts URL Scheme

Apple Shortcuts는 URL Scheme을 통해 외부 앱에서 단축어를 실행할 수 있다.

기본 형태:

```text
shortcuts://run-shortcut?name=[shortcut-name]&input=text&text=[url-encoded-payload]
```

x-callback-url 형태:

```text
shortcuts://x-callback-url/run-shortcut?name=[shortcut-name]&input=text&text=[url-encoded-payload]&x-success=[app-callback-url]&x-cancel=[app-callback-url]&x-error=[app-callback-url]
```

대량 데이터는 URL 길이와 개인정보 노출 문제가 있으므로, 1차 구현에서는 `input=clipboard` 또는 URL payload 크기 제한을 함께 검토한다.

권장 1차:

```text
shortcuts://x-callback-url/run-shortcut?name=SoheeGroupSMS&input=clipboard&x-success=com.lucid47.outboundsales:/group-sms/complete?campaignId=...
```

앱은 실행 직전에 JSON payload를 클립보드에 넣고 Shortcuts를 연다. 단축어는 클립보드 또는 Shortcut Input에서 payload를 읽는다.

주의:

- 클립보드 사용은 iOS 개인정보 알림이 표시될 수 있다.
- URL에 고객정보를 직접 싣는 것보다 대량 payload에는 실용적이다.
- 보안이 더 필요하면 Base64 인코딩 또는 간단한 서명/검증 필드를 추가한다.

## 개발 방향 결론

`자체 앱 내 Shortcuts 연동 모듈` 방식으로 개발한다.

이유:

- 기존 고객리스트, 고객 상태, 문자 템플릿, 기록 탭과 직접 연결 가능
- 사용자의 실제 iPhone 번호와 문자 요금제를 사용
- 서버 문자 API 비용 없음
- 단톡방 생성을 피하고 개별 발송에 가까운 자동화 가능
- 앱 내부에서 발송 대상/메시지/요청 로그를 관리 가능

대체안:

- 상용 앱 연동: 빠르지만 고객 데이터와 히스토리 통합이 약함
- CPaaS/Twilio/Naver Cloud SMS 등 서버 발송: 전달 상태 추적은 좋지만 비용, 발신번호, 국내 규제/인증, 개인정보 위탁 이슈가 큼
- MessageUI 반복 호출: App Store 정책에는 안전하지만 사용자가 매번 전송 버튼을 눌러야 하므로 대량 발송 UX가 나쁨

## 기능 요구사항

### 대상 선택

지원 대상:

- 현재 선택된 고객리스트 전체
- 고객 탭 필터 결과
  - 미방문
  - 완료
  - 전체
  - 검색 결과
- 오늘 스케줄 고객
- 지도에서 선택한 고객
- 사용자가 개별 체크한 고객

제외 규칙:

- 전화번호가 없는 고객 제외
- 전화번호 정규화 실패 고객 제외
- 중복 전화번호는 기본적으로 1회만 발송
- 완료 고객 제외 옵션 제공
- 이미 최근 발송한 고객 제외 옵션 제공

### 메시지 작성

지원:

- 기존 문자 템플릿 재사용
- 새 단체문자 템플릿 작성
- 개인화 치환
  - `{고객명}`
  - `{이름}`
  - `{연락처}`
  - `{주소}`
  - `{메모}`
  - `{리스트명}`
- 대상별 미리보기
- 빈 치환값 경고
- 발송 전 전체 대상 수, 제외 대상 수, 중복 수, 전화번호 없음 수 표시

### 발송 방식

1차 구현의 기본 방식:

- 앱에서 발송 캠페인 생성
- 대상별 메시지를 JSON payload로 구성
- payload를 클립보드 또는 URL text input으로 전달
- Shortcuts의 전용 단축어 `SoheeGroupSMS` 실행
- 단축어가 각 항목을 순회하면서 1명씩 메시지 발송
- 각 발송 사이에 대기 시간 적용
- 단축어 완료 후 x-success로 앱 복귀
- 앱은 캠페인을 `발송 요청 완료`로 기록

단축어 내부 요구:

- JSON 파싱
- Repeat with each item
- 각 item에서 phone/body 추출
- Send Message 액션 사용
- 수신자는 항상 1명만 지정
- `Show When Run` 또는 실행 시 표시 옵션을 꺼서 자동화에 가깝게 동작
- 항목 사이에 Wait 1~3초
- 마지막에 앱 callback URL 열기

### 발송 속도 제어

기본값:

- 메시지 간 대기: 2초
- 사용자가 1~10초 범위에서 변경 가능
- 30명 또는 50명 단위 분할 발송 검토

목적:

- 통신사 스팸 필터링 위험 감소
- 단축어 실행 안정성 증가
- 사용자가 중간 취소할 여지 확보

### 로그

중요한 한계:

- iOS/Shortcuts 방식으로는 실제 SMS 최종 도달 여부를 앱이 알 수 없다.
- x-success는 단축어가 끝났다는 뜻이지, 통신사 전달 성공 보장이 아니다.

따라서 로그 용어는 엄격하게 구분한다.

- `준비됨`: 앱에서 캠페인 생성
- `단축어 실행`: Shortcuts 호출
- `발송 요청 완료`: x-success로 복귀
- `사용자 취소`: x-cancel 수신
- `단축어 오류`: x-error 수신
- `확인 필요`: 앱이 결과를 확정할 수 없는 상태

고객별 로그:

- 고객 ID
- 고객리스트 ID
- 캠페인 ID
- 전화번호
- 렌더링된 메시지 본문
- 순번
- 요청 시각
- 추정 상태

기록 탭에서는 “발송 성공”이 아니라 “발송 요청” 또는 “문자 발송 요청”으로 표시한다.

## 데이터 모델 초안

### GroupSmsCampaign

- `id`
- `customerListId`
- `title`
- `templateId`
- `templateBody`
- `recipientCount`
- `excludedCount`
- `duplicateCount`
- `missingPhoneCount`
- `delaySeconds`
- `status`
- `createdAt`
- `startedAt`
- `completedAt`
- `shortcutName`

### GroupSmsRecipient

- `id`
- `campaignId`
- `customerListId`
- `customerId`
- `customerName`
- `phoneNumber`
- `messageBody`
- `orderIndex`
- `status`
- `createdAt`
- `updatedAt`

### 상태값 후보

```text
draft
ready
shortcutOpened
requested
cancelled
shortcutFailed
unknown
```

## UI 구조

### 진입 위치

우선순위:

1. 고객 탭 상단 또는 고객리스트 카드: `단체문자`
2. 고객 목록 선택 모드: 선택 고객에게 `단체문자`
3. 오늘 탭: 오늘 스케줄 고객에게 `단체문자`
4. 기록/히스토리: 필터링된 고객에게 재발송은 추후

### 화면 흐름

1. 대상 선택 화면
   - 현재 리스트/필터/선택 고객 확인
   - 제외 대상 요약
   - 체크박스로 대상 제외 가능

2. 메시지 작성 화면
   - 템플릿 선택
   - TextEditor
   - 치환 태그 삽입 버튼
   - 대상별 미리보기

3. 발송 준비 화면
   - 대상 수
   - 대기 시간
   - 단축어 설치 상태 안내
   - 개인정보/전송 결과 한계 안내
   - `단축어로 발송 시작`

4. 복귀 결과 화면
   - 발송 요청 완료/취소/오류
   - 캠페인 상세 로그
   - 기록 탭으로 이동

## 단축어 온보딩

필수 화면:

- 단체문자 기능 첫 실행 시 전용 단축어 설치 안내
- 단축어 이름: `SoheeGroupSMS`
- 사용자가 단축어를 삭제했을 수 있으므로 오류 발생 시 재설치 안내
- 단축어 권한 승인 안내
  - 메시지 보내기 권한
  - 클립보드 또는 입력값 사용
  - 앱 복귀 URL 열기

단축어 배포 방식 후보:

1. iCloud Shortcuts 공유 링크 제공
2. 앱 내 단계별 생성 가이드 제공
3. 장기적으로 `.shortcut` 파일 또는 웹 가이드 페이지 제공 검토

1차 MVP에서는 설치 링크와 스크린샷 가이드를 제공하는 방식이 가장 빠르다.

## 현재 앱과의 통합 포인트

이미 있는 기능:

- `MessageTemplate`
- 단일 고객 `MessageComposerSheet`
- `ContactLog`
- iOS 연락처 가져오기/그룹 가져오기
- 고객별 히스토리
- Google Drive 백업/복원

추가 필요:

- Group SMS 전용 캠페인/수신자 모델
- 캠페인 저장/조회
- payload builder
- Shortcuts bridge manager
- 앱 URL callback 처리
- 기록 탭/고객 히스토리 표시
- Google Drive 백업/복원에 캠페인/수신자 로그 포함

현재 iOS 앱은 `SceneDelegate`에서 `OutboundSalesRootView`를 띄우므로 URL callback 처리를 위해 다음 중 하나가 필요하다.

- `SceneDelegate.scene(_:openURLContexts:)`에서 NativeAppState로 전달
- 또는 SwiftUI 루트에 `.onOpenURL` 연결

기존 Google Drive OAuth도 같은 URL scheme `com.lucid47.outboundsales`를 사용하므로 path 기반으로 분기한다.

예:

```text
com.lucid47.outboundsales:/oauth2redirect
com.lucid47.outboundsales:/group-sms/complete?campaignId=...
com.lucid47.outboundsales:/group-sms/cancel?campaignId=...
com.lucid47.outboundsales:/group-sms/error?campaignId=...
```

## 보안 및 개인정보

- payload에는 고객 전화번호와 메시지 본문이 들어간다.
- URL query에 큰 JSON을 직접 넣으면 로그/클립보드/디버그 출력에 노출될 수 있다.
- 1차는 클립보드 기반 전달을 사용하되, 사용자에게 안내한다.
- payload에는 `campaignId`, `items`, `delaySeconds`, `callbackURL`만 포함한다.
- Google Drive 백업에는 캠페인 로그가 포함되므로 개인정보 백업 범위에 명시한다.

## 구현 단계

### Phase 1 - 안전한 수동/준자동 기반

- Group SMS 문서/명세 확정
- 선택 고객 목록 만들기
- 메시지 템플릿 및 치환 미리보기
- 캠페인/수신자 로그 모델 추가
- MessageUI 기반 수동 개별 발송 fallback 검토

### Phase 2 - Shortcuts 연동 MVP

- `SoheeGroupSMS` payload builder
- 클립보드 기반 payload 전달
- Shortcuts URL 실행
- x-success/x-cancel/x-error callback 처리
- 캠페인 상태 업데이트
- 고객별 “문자 발송 요청” 이력 표시

### Phase 3 - 사용성 강화

- 단축어 설치 온보딩
- 단축어 미설치/실패 복구 안내
- 대기 시간/분할 발송 설정
- 최근 캠페인 재사용
- 발송 대상 저장/재발송

### Phase 4 - 안정성 및 고급 기능

- 단축어 버전 관리
- payload 크기 제한 대응
- 단축어 출력 result 파싱
- 중간 실패/부분 완료 표현
- App Shortcuts/App Intents와 연계 가능성 검토

## 1차 개발 판단

바로 구현할 1차 MVP는 다음으로 제한한다.

- 고객 탭에서 현재 고객리스트 대상으로 진입
- 대상 체크/제외
- 기존 문자 템플릿 선택 및 본문 수정
- `{고객명}`, `{주소}` 치환
- 발송 전 미리보기
- 클립보드 payload 생성
- Shortcuts 실행 URL 열기
- callback 수신 시 캠페인 로그 저장
- 기록 탭에 캠페인 단위 이력 표시

이 범위가 가장 빠르게 검증 가능하고, 문서 요구사항의 핵심인 “단톡방 없는 순차 개별 발송” 방향을 가장 잘 반영한다.
