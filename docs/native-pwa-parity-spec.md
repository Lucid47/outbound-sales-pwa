# 네이티브 앱 전환 재현 사양서

이 문서는 현재 PWA 앱을 iPhone/iPad 네이티브 앱으로 전환할 때, 기능과 화면을 최대한 동일하게 재현하기 위한 기준 문서입니다.

목표는 “비슷한 앱”이 아니라, 사용자가 기존 PWA에서 익힌 조작 방식과 화면 흐름을 네이티브 앱에서도 그대로 사용할 수 있게 만드는 것입니다.

## 반드시 참조할 원본

네이티브 앱 개발자는 아래 파일을 기준 원본으로 삼아야 합니다. 이 문서는 요약/해설 문서이고, 실제 구현의 최종 기준은 현재 저장소의 PWA 원본 파일입니다.

```text
기능/상태/화면 흐름: src/App.tsx
시각 스타일/레이아웃: src/App.css
데이터 모델: src/db/appDb.ts
Google Drive 동기화: src/googleDriveSync.ts
PWA manifest/icon: vite.config.ts, public/
```

### 원본 파일 직접 참조 규칙

네이티브 앱을 구현하거나 수정할 때는 아래 원칙을 따릅니다.

1. `src/App.tsx`를 열어 실제 화면 분기, 탭 구성, 버튼 노출 조건, 팝업/시트 동작, 상태 변경 흐름을 확인합니다.
2. `src/App.css`를 열어 실제 색상, 간격, 카드 모양, 버튼 크기, 하단 탭바, 반응형 grid, 지도 영역, 팝업/시트 스타일을 확인합니다.
3. `src/db/appDb.ts`를 열어 고객, 고객리스트, 스케줄, 로그, 문자 템플릿, 동기화 메타데이터의 필드와 관계를 확인합니다.
4. `src/googleDriveSync.ts`를 열어 Google Drive appDataFolder 동기화 방식, 백업 파일 구조, 충돌/복원 흐름을 확인합니다.
5. 문서 설명과 원본 코드가 다르게 보이면 원본 코드를 우선합니다. 다만 사용자가 이후 대화에서 명시적으로 변경 요청한 내용이 문서에 반영되어 있다면, 그 변경 요청을 우선합니다.
6. 네이티브 구현자가 PWA와 다르게 구현해야 하는 경우, 변경 이유를 코드 주석이 아니라 개발 문서 또는 이슈에 남깁니다.

즉, 이 문서만 읽고 대략 비슷하게 만드는 것이 아니라, 위 PWA 파일을 구현 입력 자료로 직접 읽고 화면과 동작을 대조하면서 포팅해야 합니다.

### 네이티브 제약 예외 규칙

네이티브 앱은 iOS/iPadOS의 보안, 권한, 시스템 앱 연동 제약을 거스를 필요는 없습니다. 아래 경우에는 PWA와 픽셀 단위로 완전히 같지 않아도 됩니다.

- 전화, 문자, 지도, 위치 권한처럼 iOS 시스템 API가 사용자 확인 또는 앱 전환을 요구하는 경우
- Google 로그인/Drive 동기화처럼 네이티브 OAuth 흐름이 웹과 다른 경우
- iOS 안전영역, Dynamic Type, 키보드, 시트, 파일 선택기, 사진 권한처럼 운영체제 기본 UI를 따르는 편이 더 안전한 경우
- iPad split view, 회전, 멀티태스킹 때문에 화면 폭이 PWA 브라우저와 달라지는 경우

이 경우에도 기능 목적과 사용 흐름은 PWA와 같아야 합니다. 예를 들어 문자 자동 전송이 iOS에서 불가능하면, PWA와 동일하게 “문자앱을 열고 수신자/본문을 채운 뒤 사용자가 직접 전송”하는 흐름을 유지합니다.

현재 운영 중인 PWA:

```text
https://lucid47.github.io/outbound-sales/
```

네이티브 앱 구현 중 화면 판단이 애매할 때는 문서보다 PWA 실제 화면과 `src/App.css`를 우선합니다.

## 네이티브 앱 포팅 원칙

1. 기능 이름과 사용 흐름은 PWA와 동일하게 유지합니다.
2. 하단 탭 구조는 PWA와 동일하게 유지합니다.
3. “설정”은 상단 톱니바퀴가 아니라 하단 탭입니다.
4. 고객 검색창은 고객 탭의 필터 아래, 고객 목록 위에 둡니다.
5. 운전 중 손쉬운 터치를 위해 주요 버튼은 작게 만들지 않습니다.
6. 카드 모서리는 기본 8px 계열을 유지합니다.
7. 네이티브 기본 List만 사용해 화면을 만들면 PWA와 달라지므로, parity가 필요한 화면은 커스텀 카드/패널로 구현합니다.
8. 지도, 고객 카드, 문자 시트, 설정 화면은 PWA의 실제 배치를 기준으로 합니다.
9. 완료 고객은 삭제하거나 숨기는 것이 아니라 상태 전환 가능해야 합니다.
10. 히스토리는 방문 목적보다 “고객 터치 이력”을 남기는 것이 핵심입니다.

## 현재 PWA 하단 탭

PWA의 현재 하단 탭은 5개입니다.

```text
오늘
고객
가져오기
기록
설정
```

네이티브 앱도 1차 parity 목표에서는 같은 5개 탭을 사용합니다.

주의:

- 현재 native 브랜치에는 별도 `지도` 탭이 존재할 수 있습니다.
- PWA와 동일하게 만들려면 지도는 별도 하단 탭이 아니라 `오늘` 탭의 지도 모드와 `고객` 탭 안의 고객 위치 지도로 제공해야 합니다.
- 지도 탭을 유지하려면 이는 PWA parity가 아니라 네이티브 확장 기능으로 분류해야 합니다.

## 데이터 모델 parity

PWA 데이터 모델은 `src/db/appDb.ts`가 기준입니다.

### CustomerList

```text
id
name
companyName
sourceFileName
importedAt
createdAt
updatedAt
```

역할:

- 하나의 고객사에서 받은 고객리스트 단위입니다.
- import한 CSV 파일 하나가 하나의 CustomerList가 됩니다.
- 수동으로 빈 고객리스트를 만들 수도 있습니다.
- 고객, 로그, 스케줄은 반드시 customerListId로 이 리스트에 연결됩니다.

### Customer

```text
id
customerListId
name
phoneNumber
address
birthDate?
notes
latitude?
longitude?
coordinateSource?
geocodedAt?
geocodeQuery?
region?
status
createdAt
updatedAt
```

상태:

```text
open
done
hold
needsGeocode
```

현재 주요 사용 상태:

- `open`: 활성 고객
- `done`: 완료 고객

완료 고객은 되돌릴 수 있어야 합니다.

### ContactLog

```text
id
customerListId
customerId
type
templateId?
messageBody?
result
createdAt
```

type:

```text
call
manualSms
templateSms
note
statusComplete
statusReopen
```

result:

```text
opened
sentByUser
completed
reopened
saved
cancelled
unknown
```

중요:

- 실제 통화 성공 여부가 아니라 전화 버튼을 누른 사실을 남깁니다.
- 실제 문자 발송 여부가 아니라 문자 버튼을 누른 사실을 남깁니다.
- 고객 응대 히스토리는 ContactLog 중심으로 누적합니다.

### VisitLog

```text
id
customerListId
customerId
visitedAt
result
memo?
createdAt
```

현재 result는 `completed` 중심입니다.

### VisitSchedule

```text
id
customerListId
date
title
createdAt
updatedAt
```

### VisitScheduleItem

```text
id
scheduleId
customerListId
customerId
orderIndex
status
completedAt?
```

status:

```text
pending
completed
skipped
hold
```

### MessageTemplate

```text
id
title
body
isDefault
createdAt
updatedAt
```

기본 템플릿도 수정 가능해야 합니다.

## 저장과 동기화 parity

PWA:

```text
로컬 저장: IndexedDB + Dexie
동기화: Google Drive appDataFolder
사용자 백업: 일반 Google Drive JSON 파일
```

네이티브 1차:

```text
로컬 저장: 앱 샌드박스 Application Support JSON
백업: JSON 파일 내보내기/가져오기
동기화: 이후 Google Drive 연결
```

네이티브가 동일 기능을 갖추려면 아래 동작을 보장해야 합니다.

- 앱 재실행 시 이전 데이터 자동 로드
- 고객리스트, 고객, 로그, 스케줄, 템플릿 모두 저장
- 고객리스트 삭제 시 해당 리스트의 고객, 로그, 스케줄도 함께 삭제
- Google Drive 동기화 연결 전에도 로컬 데이터는 유지
- 새 기기 복원 흐름 제공

## CSV import parity

PWA 요구사항:

- CSV 첫 행을 헤더로 해석합니다.
- 헤더명으로 열 의미를 자동 매핑합니다.
- 사용자가 매핑을 확인/수정할 수 있습니다.
- 헤더가 없거나 실제 데이터와 구분하기 어려운 경우 사용자가 첫 행 헤더 사용을 끄고 각 열을 직접 매핑할 수 있습니다.
- 고객사 이름과 고객리스트 이름은 사용자가 입력합니다.
- 기본값을 강제로 넣지 않고 placeholder만 보여줍니다.

필드 alias:

```text
name: 고객명, 고객이름, 이름, 성명, 수령인, 받는분, 받는 사람, 거래처명, 회사명, name
phoneNumber: 연락처, 전화번호, 휴대폰, 핸드폰, 휴대전화, 휴대폰번호, 핸드폰번호, mobile, phone, tel, telephone
address: 주소, 우편물주소, 우편물수령지, 우편물 수령지, 우편수령지, 수령지, 배송지, 도로명주소, 지번주소, address
birthDate: 생년월일, 생일, 출생일, birth, birthday
notes: 기타사항, 비고, 메모, notes, memo
latitude: 위도, lat, latitude
longitude: 경도, lng, lon, longitude
```

헤더 없는 CSV:

- `첫 행을 헤더로 사용`을 끄면 첫 행도 데이터로 유지합니다.
- 컬럼명은 `열1`, `열2`, `열3`처럼 자동 생성합니다.
- 사용자는 각 열을 고객명, 연락처, 주소, 생년월일, 메모, 위도, 경도 중 필요한 필드에 직접 연결합니다.
- 고객명은 필수이며, 연락처 또는 주소 중 하나 이상이 매핑되어야 저장합니다.

헤더 정규화:

- 공백 제거
- `_` 제거
- `-` 제거
- 소문자화
- 끝 숫자 제거

예:

```text
핸드폰1 → 핸드폰
핸드폰2 → 핸드폰
```

고객 저장 조건:

- 이름이 없으면 저장하지 않습니다.
- 연락처와 주소가 모두 없으면 저장하지 않습니다.
- 생년월일은 가능한 경우 ISO 형태로 정규화합니다.

## 연락처 일괄 등록 parity

목표:

- 가져오기 완료 후 고객 데이터를 iOS 연락처에 바로 등록할 수 있어야 합니다.
- 이미 저장된 고객리스트에서도 나중에 같은 기능을 실행할 수 있어야 합니다.
- 고객리스트 이름과 같은 연락처 리스트/그룹을 만들고, 등록된 고객을 해당 그룹에 배정합니다.
- 카카오톡 자동등록 방지를 위해 기본적으로 연락처 이름 앞에 `#` 접두어를 붙입니다.

진입점:

- 가져오기 탭:
  - 파일에서 가져오기
  - 사진에서 가져오기
  - 텍스트로 붙여넣기
  - 헤더/열 매핑 저장 완료 후 `연락처에도 등록` 옵션 제공
- 고객 탭:
  - 현재 선택된 고객리스트 상단에 `연락처 등록` 버튼 제공
  - 이미 저장된 리스트도 언제든 연락처 등록 가능

등록 전 팝업:

- 고객리스트 이름 입력 또는 기존 이름 확인
- 연락처 그룹/리스트 이름 확인
- 이름 접두어 입력
  - 기본값: `#`
  - 예: `홍길동` → `#홍길동`
- 이름 접미어 입력
  - 기본값: 비어 있음
- 등록 대상 미리보기
  - 전체 고객 수
  - 전화번호 있는 고객 수
  - 전화번호 없는 고객 수
  - 중복 후보 수
- 중복 처리 방식 선택
  - 건너뛰기
  - 기존 연락처 업데이트
  - 새 연락처로 추가

저장 규칙:

- iOS Contacts framework의 `CNContactStore`와 `CNSaveRequest`를 사용합니다.
- 연락처 권한이 없으면 등록 전에 시스템 권한 요청을 표시합니다.
- 연락처 그룹/리스트는 `CNMutableGroup`으로 생성합니다.
- 새 연락처는 `CNMutableContact`로 생성합니다.
- 고객 전화번호는 `CNPhoneNumber`로 저장합니다.
- 주소가 있는 경우 가능한 범위에서 우편주소 필드로 저장합니다.
- 메모에는 앱 이름, 원본 고객리스트 이름, 원본 고객 ID를 남깁니다.
- 연락처와 그룹은 같은 Contacts 컨테이너에 생성해야 합니다.
- 등록 후 고객 데이터에는 연락처 등록 상태를 저장합니다.
  - 미등록
  - 등록 완료
  - 중복으로 건너뜀
  - 실패

등록 결과:

- 완료 후 요약 팝업을 표시합니다.
  - 신규 등록 수
  - 업데이트 수
  - 건너뛴 수
  - 실패 수
- 실패 항목은 고객명, 전화번호, 실패 원인을 보여줍니다.
- 실패 항목만 다시 시도할 수 있어야 합니다.

주의:

- `#` 접두어는 카카오톡 자동등록 방지 목적의 기본값입니다.
- 사용자가 접두어를 비우고 저장하려는 경우 확인 팝업을 표시합니다.
- 연락처 등록은 사용자의 시스템 연락처를 변경하므로 실행 전 미리보기와 명시적 저장 버튼이 필요합니다.

## 주소 처리 parity

주소 처리는 `src/App.tsx`의 주소 정규화 함수와 `native/OutboundSalesCore/Sources/OutboundSalesCore/AddressUtilities.swift`를 기준으로 합니다.

### 그룹화 주소

지역별 그룹화는 도로명까지만 사용합니다.

예:

```text
산성대로 123 → 산성대로
공원로 360 → 공원로
```

### 지도/길찾기 주소

지도 검색과 티맵 전달은 `도로명 + 건물번호`까지만 사용합니다.

예:

```text
경기도 성남시 수정구 산성대로 123, 302호 → 산성대로 123
```

아래 항목은 제거합니다.

- 동/호수
- 괄호 안 설명
- 고객명
- 불필요한 상세 설명

## 지도 parity

PWA 지도:

- Leaflet + OpenStreetMap
- 고객명 라벨로 표시
- 완료/미완료/예정 상태를 라벨에 반영
- 라벨 터치 시 작은 고객 카드 팝업 표시
- 팝업에서 전화, 문자, 메모, 길찾기, 이력, 완료/완료취소, 스케줄 추가 가능
- 내 위치 버튼
- 지도 하단에 표시 실패 고객과 원인 표시

네이티브 지도:

- MapKit 사용
- 단순 Marker만으로 끝내지 말고 고객명 라벨과 상태 표시를 우선 구현합니다.
- 선택한 고객 라벨에서 PWA 팝업 카드와 같은 액션을 제공해야 합니다.
- 지도 위치 누락 고객 목록을 고객 탭 지도 아래에 표시해야 합니다.
- 별도 지도 탭은 확장 기능으로만 유지합니다.
- 핀/라벨은 고객명만 보이는 단순 제목이 아니라 완료/미완료 상태를 함께 보여야 합니다.

## 전화/문자 parity

전화:

- PWA는 `tel:` 링크를 사용합니다.
- 네이티브는 `tel:` URL 또는 적절한 시스템 URL open을 사용합니다.
- 전화 버튼을 누르면 즉시 ContactLog `call/opened`를 남깁니다.

문자:

- PWA는 `sms:` 링크를 사용합니다.
- iOS 정책상 자동 문자 발송은 불가능합니다.
- 고객 카드, 고객 상세, 지도 팝업의 문자 버튼은 바로 문자앱을 열지 않고 일반 문자/템플릿 문자 선택 시트를 먼저 표시합니다.
- 템플릿 문자는 고객 연락처와 템플릿 본문이 입력된 문자 작성창을 엽니다.
- 사용자 문자는 고객 연락처만 입력된 문자 작성창을 엽니다.
- iOS에서 실제 전송은 사용자가 직접 눌러야 하며 앱이 자동 전송하지 않습니다.
- 문자 버튼을 누르면 ContactLog를 남깁니다.
- 실제 발송 성공 여부를 확인하려고 하지 않습니다.

중요:

- 문자앱 실행 시 현재 고객 번호만 사용해야 합니다.
- 이전 고객 번호가 재사용되지 않도록 버튼 클릭 이벤트와 대상 고객 상태를 분리합니다.

## 완료/히스토리 parity

완료 처리는 단순 방문 완료가 아니라 고객 서비스 상태 변경입니다.

완료 처리 시:

- Customer.status = `done`
- ContactLog type = `statusComplete`
- result = `completed`
- 오늘 스케줄 항목이 있으면 `completed` 처리

완료 취소 시:

- Customer.status = `open`
- ContactLog type = `statusReopen`
- result = `reopened`
- 오늘 스케줄 완료 항목은 다시 `pending` 처리

메모:

- 메모는 ContactLog type `note`로 저장합니다.
- 프리셋:
  - 전화하였으나 받지 않음
  - 문자로 연락함
  - 방문하였으나 부재
  - 사용자 템플릿

기록 탭:

- 전체 고객 수
- 터치 고객 수
- 완료 고객 수
- 고객별 히스토리
- 누적 터치/상담 히스토리
- 항목 터치 시 해당 고객 전체 히스토리 팝업

## Google Drive parity

현재 PWA OAuth:

- Google OAuth 앱은 Production 상태
- `VITE_GOOGLE_CLIENT_ID`는 GitHub Variables로 주입
- 사용자가 각자 본인 Google Drive에 저장

네이티브에서 동일 방향으로 가려면:

- Google Sign-In 또는 OAuth 흐름 필요
- Drive appDataFolder에 동일한 백업 JSON 구조 저장
- PWA와 네이티브가 같은 계정 데이터와 호환되려면 JSON schema를 유지해야 함
- 병합 정책도 PWA와 동일해야 함

현재 병합 정책:

- ID 기준 병합
- 같은 ID는 최신 수정 시각 우선
- 로그성 데이터는 ID 기준 합치기
- `Drive 데이터를 이 기기에 가져오기`는 병합이 아니라 로컬 교체 복원

## OCR parity와 확장

OCR은 PWA 본기능 parity 이후 확장 기능입니다.

현재 OCR 계획:

- Mac CLI에서 먼저 Apple Vision OCR 검증
- 이미지 파일 입력
- OCR 텍스트와 좌표 추출
- y좌표 기준 행 묶기
- x좌표 기준 열 묶기
- 셀 배열 생성
- 사용자가 열 이름 지정
- CSV 생성

네이티브 확장:

- iPhone/iPad 문서 스캔: VisionKit
- OCR: Apple Vision
- 표 복원과 CSV 생성은 Mac CLI 코어 로직 재사용
- 최종 결과는 기존 CSV import와 같은 CustomerList/Customer 저장 흐름으로 연결
- 1차 네이티브 구현은 카메라 촬영 또는 사진앱 선택 후 OCR, CSV 미리보기/수정, 고객리스트 저장 흐름을 제공합니다.
- 실제 기기 카메라 스캔 UI와 컬럼 매핑 전용 화면은 OCR 품질 검증 뒤 고도화합니다.

자세한 계획은 `docs/customer-list-ocr.md`를 기준으로 합니다.

## 네이티브 구현 우선순위

1. PWA 데이터 모델과 JSON 저장 호환
2. 하단 5탭 구조 parity
3. 고객리스트/고객/스케줄/기록 기본 화면 parity
4. 전화/문자/길찾기 액션 parity
5. 완료/완료취소/메모/히스토리 parity
6. 고객 탭 지도와 지도 팝업 parity
7. Google Drive 동기화 parity
8. OCR import 확장

## 완료 기준

네이티브 앱이 PWA와 동일하다고 판단하려면 아래 조건을 만족해야 합니다.

- 같은 CSV를 가져왔을 때 같은 고객 수와 같은 필드가 저장됩니다.
- 고객 탭에서 같은 리스트/스케줄/지도/필터/검색 순서가 보입니다.
- 카드형/목록형 전환이 iPhone/iPad에서 동작합니다.
- 전화/문자/길찾기 버튼이 같은 고객을 대상으로 실행됩니다.
- 완료/완료취소가 히스토리에 남고 되돌릴 수 있습니다.
- 기록 탭의 카운트와 히스토리가 PWA와 같은 기준으로 계산됩니다.
- JSON 백업을 통해 PWA와 네이티브 간 데이터 교환이 가능합니다.
- 화면 색상, 여백, 카드 모서리, 버튼 높이, 하단 탭 구조가 `docs/ui-reference.md`의 기준을 따릅니다.
