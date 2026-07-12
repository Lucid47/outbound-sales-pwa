# Group SMS 구현 및 Android 포팅 가이드

## 문서 목적

이 문서는 `소희야 가자`의 단체문자 기능을 다시 구현하거나 Android로 포팅할 때 바로 사용할 수 있는 기술 기준이다.

- 2026-07-12 실제 iPhone 검증 결과
- 앱과 전송 모듈 사이의 데이터 계약
- 대상 선정, 템플릿 치환, 중복 제거, 발송 간격 계산 알고리즘
- iOS Shortcuts 전송 어댑터
- Android 전송 어댑터 선택 기준과 구현 순서
- 사진/파일 첨부 확장 설계
- 상태 저장, 재시도, 중복 발송 방지, 테스트 기준

제품 요구사항과 통신사 정책은 `docs/group-sms.md`, 사람이 만드는 iOS 단축어 절차는 `docs/group-sms-shortcut.md`를 함께 본다.

단계별 문자 발송 시험 데이터, 합격 기준, 중단 조건과 결과 기록 양식은 `docs/group-sms-test-plan.md`를 따른다.

## 현재 검증 기준선

검증 환경:

- 검증일: 2026-07-12
- 기기: 실제 iPhone
- 앱: `소희야 가자` 네이티브 앱
- 단축어: `SoheeGroupSMS`
- 입력: 앱이 클립보드에 기록한 JSON
- 전송: Apple Shortcuts의 `메시지 보내기`

| 항목 | 상태 | 확인 내용 |
| --- | --- | --- |
| 앱에서 payload 생성 | 실기기 검증 완료 | 테스트 번호와 반복 횟수로 JSON 생성 |
| 클립보드 전달 | 실기기 검증 완료 | `payload만 클립보드에 복사` 사용 |
| JSON 사전 변환 | 실기기 검증 완료 | Shortcuts에서 `클립보드에서 사전 가져오기` 성공 |
| 수신자/본문 추출 | 실기기 검증 완료 | `phoneNumber`, `messageBody` 값 확인 |
| 1명 발송 | 실기기 검증 완료 | 수신자와 본문 자동 입력 및 실제 수신 확인 |
| 여러 번호 순차 발송 | 실기기 검증 완료 | 수신자별 1:1 메시지 반복 |
| 동일 번호 반복 발송 | 실기기 검증 완료 | 반복 횟수 증가 후 정상 발송 |
| 무확인 자동 발송 | 실기기 검증 완료 | `알림 보기` 제거, `실행 시 보기` 끔 |
| 고정/랜덤 딜레이 | 미검증 | 앱은 값을 생성하지만 단축어 `대기` 연결 필요 |
| 완료/취소/오류 callback | 미검증 | 앱 코드는 있으나 실제 단축어 연결 검증 필요 |
| 사진 첨부 | 설계/검증 전 | 단축어 단위 시험 후 App Intent 연결 예정 |
| 일반 파일 첨부 | 설계/검증 전 | iMessage/RCS/MMS 호환성 시험 필요 |
| 실제 통신사 도달 확인 | 직접 확인 불가 | 앱은 전송 요청과 단축어 완료까지만 확인 가능 |

이 표에서 `구현됨`과 `실기기 검증 완료`를 혼용하지 않는다. 새 기기 또는 새 OS에서 시험할 때마다 검증일과 결과를 갱신한다.

## 전체 아키텍처

플랫폼 공통 영역과 플랫폼별 전송 영역을 분리한다.

```text
Customer Repository
        |
        v
Target Selector -> Phone Normalizer -> Duplicate Filter
        |
        v
Template Renderer -> Delay Planner -> Campaign Builder
        |
        v
Outbox Store / Policy Guard / Audit Log
        |
        +---------------------+
        |                     |
        v                     v
iOS Shortcut Transport   Android Transport
        |                 - User Confirming Intent
        |                 - Default SMS App
        |                 - Server SMS API
        v
Platform message service
```

공통 엔진은 수신자와 메시지를 결정할 뿐 직접 SMS API를 호출하지 않는다. 실제 발송은 `MessageTransport` 구현체가 담당한다.

향후 독립 단체문자 앱으로 분리할 수 있도록 공통 엔진은 `Customer`, `NativeAppState`, 특정 Bundle ID, 특정 단축어 이름에 의존하지 않는다. 현재 결합 지점의 제거 순서와 제품별 어댑터 구조는 `docs/group-sms-productization-plan.md`를 따른다.

## 권장 모듈 경계

현재 Swift 프로젝트:

```text
native/OutboundSalesCore/
  GroupSMS.swift                 공통 캠페인 모델과 빌더

native/OutboundSalesNative/
  GroupSmsTestView.swift         캠페인 작성/검증 UI
  NativeAppState.swift           캠페인 저장과 callback 처리

native/OutboundSalesiOS/
  AppDelegate/SceneDelegate      URL callback 진입점
  GroupSmsAppIntents.swift       향후 첨부파일 Shortcuts 제공
```

Android 포팅 시 권장 구조:

```text
android/app/src/main/java/.../
  groupsms/domain/
    GroupSmsModels.kt
    CampaignBuilder.kt
    TemplateRenderer.kt
    PhoneNormalizer.kt
    DelayPlanner.kt
    PolicyGuard.kt
  groupsms/data/
    CampaignRepository.kt
    RoomCampaignRepository.kt
  groupsms/transport/
    MessageTransport.kt
    SmsIntentTransport.kt
    DefaultSmsTransport.kt
    ServerSmsTransport.kt
  groupsms/worker/
    GroupSmsWorker.kt
  groupsms/ui/
    GroupSmsComposeScreen.kt
```

Swift와 Kotlin이 소스 코드를 직접 공유하지는 않는다. 대신 JSON Schema, 상태값, 알고리즘 테스트 벡터를 공유해 같은 입력이 같은 캠페인을 만들도록 한다.

## 공통 데이터 계약

### Campaign

```json
{
  "schemaVersion": 1,
  "campaignId": "UUID",
  "campaignTitle": "반복 테스트",
  "createdAt": "ISO-8601",
  "platform": "ios",
  "transport": "ios-shortcuts",
  "status": "ready",
  "recipients": [],
  "attachments": []
}
```

### RecipientJob

```json
{
  "id": "UUID",
  "campaignId": "UUID",
  "customerId": "UUID-or-null",
  "displayName": "홍길동",
  "phoneNumber": "01012345678",
  "messageBody": "홍길동 고객님, 안내드립니다.",
  "orderIndex": 0,
  "plannedDelaySeconds": 0,
  "idempotencyKey": "SHA256(campaignId|phoneNumber|orderIndex)",
  "status": "pending",
  "attemptCount": 0,
  "lastError": null,
  "attachmentIds": []
}
```

### Attachment

```json
{
  "id": "UUID",
  "kind": "photo",
  "fileName": "notice.jpg",
  "contentType": "image/jpeg",
  "byteCount": 123456,
  "orderIndex": 0,
  "checksum": "hex-digest",
  "localReference": "platform-private-reference"
}
```

캠페인의 `attachments`는 위 객체의 순서 있는 배열이며 `kind`는 `photo` 또는 `file`이다. `localReference`에는 절대 경로나 고객이 볼 수 있는 개인정보를 동기화하지 않는다. 백업 시 파일을 별도 자산으로 저장하고 복원 후 새 로컬 참조를 만든다.

### 상태값

캠페인 상태:

```text
draft -> ready -> dispatching -> requestCompleted
                         |-> cancelled
                         |-> failed
                         |-> unknown
```

수신자 작업 상태:

```text
pending -> dispatching -> requested
                    |-> failed
                    |-> skipped
                    |-> cancelled
```

`requested`는 단말 전송 API 또는 단축어에 요청했다는 뜻이다. `delivered`라는 이름은 전달 영수증을 실제로 받은 경우에만 사용한다.

## 캠페인 생성 알고리즘

### 1. 대상 수집

입력은 고객리스트, 오늘 스케줄, 검색 결과 또는 사용자가 선택한 고객 ID 목록이다.

```text
candidates = repository.load(scope)
candidates = candidates.filter(userSelection)
candidates = candidates.filter(notExcludedByStatus)
```

대상 순서는 사용자가 화면에서 확인한 순서를 기본으로 유지한다. 지도/스케줄 최적화가 적용된 경우에만 명시적으로 정렬한다.

### 2. 전화번호 정규화

한국 휴대전화 기준 1차 알고리즘:

```text
normalize(raw):
  1. Unicode 공백과 구분기호 제거
  2. 숫자와 맨 앞의 +만 유지
  3. +82 또는 82로 시작하는 국제번호를 국내 형식으로 변환
  4. 국제번호 제거 후 첫 0이 없으면 0 추가
  5. 10~11자리인지 확인
  6. 휴대전화 전용 모드에서는 010 시작 여부 확인
  7. 저장/비교 키는 숫자 전용 문자열 사용
```

예:

```text
010-1234-5678      -> 01012345678
+82 10 1234 5678   -> 01012345678
82-10-1234-5678    -> 01012345678
```

원본 번호는 고객 데이터에 유지하고, 정규화 번호는 캠페인 작업에 별도 저장한다.

### 3. 중복 제거

기본 중복 키는 정규화 전화번호다.

```text
seen = Set<String>()
result = []
for customer in candidates:
  phone = normalize(customer.phone)
  if invalid(phone): record exclusion; continue
  if removeDuplicates and seen.contains(phone): record duplicate; continue
  seen.insert(phone)
  result.append(customer, phone)
```

중복 제거 결과에는 제외된 고객 ID와 대표 발송 고객 ID를 함께 기록해 사용자가 검토할 수 있게 한다.

### 4. 템플릿 렌더링

지원 키는 명시적인 허용 목록으로 관리한다.

```text
{고객명}, {이름}, {연락처}, {주소}, {메모}, {리스트명}, {순번}, {전체}
```

```text
render(template, customer, index, total):
  values = approvedPlaceholderMap(customer, index, total)
  output = template
  for each approved key:
    output = output.replace("{" + key + "}", values[key])
  unresolved = findAll(/\{[^{}]+\}/)
  if unresolved is not empty: return validation error
  if output.trim is empty: return validation error
  return output
```

임의 코드 실행형 템플릿이나 정규식 치환을 사용자 입력으로 허용하지 않는다.

### 5. 딜레이 계획

딜레이는 실행 중 다시 계산하지 않고 캠페인 생성 시 각 작업에 확정해 저장한다. 그래야 재시작과 감사 로그가 일치한다.

```text
delay(orderIndex, settings):
  if orderIndex == 0: return 0
  if batchRestEnabled and orderIndex % batchSize == 0:
    return random(batchMinRestSeconds...batchMaxRestSeconds)
  switch mode:
    off: return 0
    fixed: return fixedDelaySeconds
    random: return random(minDelaySeconds...maxDelaySeconds)
```

무작위 재현이 필요한 테스트에서는 `campaignId`를 seed로 사용하는 의사난수 생성기를 주입한다. 운영에서는 시스템 난수를 사용할 수 있지만 결과값은 반드시 작업에 저장한다.

### 6. 정책 보호선

발송 전에 다음 값을 합산한다.

```text
projectedToday = storedRequestedToday + currentCampaignCount + manualAdjustment
projectedMonth = storedRequestedMonth + currentCampaignCount + manualAdjustment
```

정책 판단은 UI 문구와 분리된 순수 함수로 만든다.

```text
evaluate(projectedToday, daysOver200ThisMonth, campaignCount)
  -> allow | warn | requireExplicitConfirmation | block
```

통신사 정책값은 앱 업데이트 없이 바꿀 수 있도록 설정 객체로 관리하되, 서버가 없는 버전은 앱 설정과 문서 버전을 함께 기록한다.

## 중복 발송 방지와 재시도

각 작업에 아래 키를 만든다.

```text
idempotencyKey = SHA256(campaignId + "|" + normalizedPhone + "|" + orderIndex)
```

전송 직전에 작업 상태를 `dispatching`으로 저장하고, 전송 API 호출 후 `requested` 또는 `failed`로 갱신한다.

앱이나 단축어가 중단된 경우:

- `pending`: 아직 요청하지 않은 것으로 간주
- `requested`: 자동 재전송 금지
- `dispatching`: 결과 불명 상태로 표시하고 사용자 확인 없이 자동 재전송 금지
- `failed`: 오류 원인과 재시도 가능 여부를 확인한 후 명시적 재시도

iOS Shortcuts 1차 방식은 수신자별 callback이 없으므로 캠페인 중간의 정확한 진행 상태를 알 수 없다. 따라서 중단된 캠페인을 자동 이어보내지 않고 `확인 필요`로 처리한다.

## iOS 구현

### 앱 역할

1. 대상과 템플릿을 검증한다.
2. `RecipientJob` 배열과 딜레이를 확정한다.
3. payload JSON을 클립보드에 복사한다.
4. `shortcuts://x-callback-url/run-shortcut`을 연다.
5. callback URL을 받아 캠페인 상태를 갱신한다.

현재 실행 URL:

```text
shortcuts://x-callback-url/run-shortcut?name=SoheeGroupSMS&input=clipboard
```

callback:

```text
com.lucid47.outboundsales:/group-sms/complete?campaignId=...
com.lucid47.outboundsales:/group-sms/cancel?campaignId=...
com.lucid47.outboundsales:/group-sms/error?campaignId=...
```

### 단축어 최소 실행 알고리즘

```text
PayloadText = 클립보드 가져오기
Payload = PayloadText에서 사전 가져오기
Recipients = Payload["recipients"]

Recipients의 각 항목 반복:
  PhoneNumber = 반복 항목["phoneNumber"]
  MessageBody = 반복 항목["messageBody"]
  DelaySeconds = 반복 항목["plannedDelaySeconds"]

  PhoneNumber에게 MessageBody 메시지 보내기
  실행 시 보기 = 끔

  if DelaySeconds > 0:
    DelaySeconds초 대기

완료 callback URL 열기
```

`알림 보기`와 검증용 `텍스트`가 반복 안에 남아 있으면 매 발송마다 사용자가 확인해야 한다. 운영 단축어에서는 제거한다.

### 권한과 보안

- 최초 메시지 전송 권한은 사용자가 직접 허용한다.
- 단축어 설치와 수정은 사용자가 Shortcuts 앱에서 수행한다.
- 클립보드에는 발송 직전에만 payload를 기록한다.
- 발송 후에는 앱이 클립보드를 지울 수 있지만 사용자가 중간에 다른 내용을 복사했는지 확인하지 못하므로 조건부 정리만 한다.
- 고객정보를 URL query에 직접 싣지 않는다.

## 첨부파일 확장

### 1차 검증

앱을 수정하기 전에 단축어에서 사진을 한 번 선택하고 같은 사진을 본인 번호에 전송한다.

1. `사진 선택`을 반복 밖에 추가
2. 사진 1장을 선택해 `SelectedAttachment` 변수로 저장
3. 수신자 1명에게 본문과 사진 전송
4. 본인 번호 2개에 같은 사진 전송
5. iPhone 수신자와 Android 수신자에서 각각 확인
6. 사진 크기, 전송 시간, MMS/RCS/iMessage 유형 기록

문자와 첨부가 한 메시지로 묶이지 않는 기기에서는 본문과 첨부가 두 개의 메시지로 전송될 수 있다. 실제 결과를 기준으로 UI에 예상 발송 건수를 표시한다.

### 앱 통합

클립보드 JSON에 바이너리를 Base64로 넣지 않는다. 용량, 메모리, 개인정보 노출 문제가 커진다.

권장 방식:

1. 앱에서 다중 선택 `PhotosPicker` 또는 다중 파일 선택기로 첨부 선택
2. 사진과 일반 파일을 하나의 순서 있는 `GroupSmsAttachment` 배열로 구성
3. 앱 전용 저장소에 모두 복사
4. 각 파일의 SHA-256, UTType/MIME type, 크기와 순서 기록
5. `AppIntent`로 여러 `IntentFile`을 반환
6. Shortcuts에서 `소희야 가자 첨부파일 가져오기` 액션 실행
7. 반복 안의 `메시지 보내기`에 반환된 파일 배열 사용
8. 캠페인 완료/취소 후 임시파일 정리

제품 범위는 캠페인 공통 사진 여러 장과 일반 파일 여러 개다. 사진과 파일의 혼합 첨부도 지원한다. 수신자별로 서로 다른 파일을 지정하는 기능은 별도 단계로 둔다.

## Android 포팅 전략

Android에서는 iOS Shortcuts를 사용할 수 없다. 배포 방식에 따라 전송 어댑터를 선택한다.

| 방식 | 자동 발송 | Play 배포 난이도 | 첨부 | 권장 용도 |
| --- | --- | --- | --- | --- |
| SMS Intent/Share Intent | 불가, 사용자 전송 필요 | 낮음 | 공유 앱에 따라 가능 | 일반 Play 앱의 안전한 기본값 |
| `SmsManager` + `SEND_SMS` | 가능 | 높음, 정책 심사 필요 | SMS/MMS API 분리 | 기본 SMS 앱 또는 승인된 핵심 기능 |
| 기본 SMS 앱 역할 | 가능 | 매우 높음 | SMS/MMS 가능 | 문자 기능이 제품 핵심인 별도 앱 |
| 서버 SMS API | 가능 | 중간 | 공급자별 상이 | 기업용 발송/전달상태 필요 시 |

Google Play는 SMS 권한을 고위험 권한으로 제한한다. 일반 CRM 부가기능만으로 `SEND_SMS` 승인이 보장되지 않는다. 기본 SMS 핸들러가 되거나 정책상 허용되는 핵심 기능과 권한 선언 심사를 통과해야 한다.

### 공통 Transport 인터페이스

```kotlin
interface MessageTransport {
    suspend fun capabilities(): TransportCapabilities
    suspend fun dispatch(job: RecipientJob): DispatchResult
    suspend fun cancel(campaignId: String)
}

data class DispatchResult(
    val state: DispatchState,
    val platformMessageId: String? = null,
    val errorCode: String? = null,
    val retryable: Boolean = false
)
```

UI와 캠페인 엔진은 `SmsManager`나 Intent를 직접 호출하지 않고 이 인터페이스만 사용한다.

### A. 일반 Play 앱

`ACTION_SENDTO`와 `smsto:` URI로 메시지 앱을 연다.

```kotlin
val intent = Intent(Intent.ACTION_SENDTO).apply {
    data = Uri.parse("smsto:${Uri.encode(job.phoneNumber)}")
    putExtra("sms_body", job.messageBody)
}
startActivity(intent)
```

장점은 SMS 권한이 필요 없다는 것이다. 단점은 사용자가 전송을 눌러야 하므로 자동 반복 요구사항을 충족하지 못한다.

### B. 기본 SMS 앱 또는 권한 승인 버전

필수 검토:

- `PackageManager.FEATURE_TELEPHONY_MESSAGING`
- 활성 SIM 목록과 기본 발신 SIM
- `SEND_SMS` 런타임 권한
- Google Play SMS/Call Log 권한 선언 승인
- 기본 SMS 역할 요청 여부
- 장문 메시지 분할
- sent/delivery `PendingIntent`

```kotlin
val sms = context.getSystemService(SmsManager::class.java)
    .createForSubscriptionId(subscriptionId)
val parts = sms.divideMessage(job.messageBody)

if (parts.size == 1) {
    sms.sendTextMessage(
        job.phoneNumber,
        null,
        job.messageBody,
        sentPendingIntent(job.id),
        deliveryPendingIntent(job.id)
    )
} else {
    sms.sendMultipartTextMessage(
        job.phoneNumber,
        null,
        parts,
        sentPendingIntents(job.id, parts.size),
        deliveryPendingIntents(job.id, parts.size)
    )
}
```

멀티 SIM 기기에서는 기본 `SmsManager`에 의존하지 않고 사용자가 선택한 `subscriptionId`로 인스턴스를 만든다.

MMS는 `sendMultimediaMessage`를 사용할 수 있지만 이동통신사 설정, APN, 데이터 연결, 기본 SMS 앱 상태와 콘텐츠 URI 요구사항이 추가된다. SMS와 동일한 구현으로 취급하지 않는다.

### Android 실행 스케줄러

짧은 전경 실행은 coroutine으로 처리할 수 있지만, 화면이 꺼지거나 앱이 백그라운드로 가는 캠페인은 WorkManager와 foreground service 정책을 검토한다.

```text
for job in repository.pendingJobs(campaignId):
  if campaign cancelled: stop
  if policy guard blocks: mark campaign paused; stop
  if job idempotency key already requested: skip

  persist job = dispatching
  result = transport.dispatch(job)
  persist result immediately

  if result is retryable:
    schedule bounded exponential retry
    stop current chain

  delay(job.plannedDelaySeconds)
```

Android의 백그라운드 제한 때문에 수십 분짜리 단일 Worker에 의존하지 않는다. 묶음 단위로 작업을 나누고 다음 묶음을 예약한다.

### Android 첨부파일

- 일반 앱: `FileProvider`의 `content://` URI와 `ACTION_SEND`/`ACTION_SENDTO`를 사용하고 사용자가 전송
- 기본 SMS 앱: MMS PDU 생성과 `sendMultimediaMessage` 검증 필요
- 서버 전송: 공급자 API의 MMS/RCS 지원 여부에 따라 별도 구현

사진은 원본을 그대로 반복 전송하지 말고 최대 해상도와 파일 크기를 정책값으로 제한한 파생본을 만든다. 원본 고객 기록은 변경하지 않는다.

## 플랫폼 공통 테스트

### 단위 테스트

- 전화번호 정규화: 하이픈, 공백, `+82`, 잘못된 길이
- 중복 제거: 같은 번호를 가진 여러 고객
- 템플릿: 모든 치환키, 빈 값, 알 수 없는 키
- 딜레이: 꺼짐/고정/랜덤/묶음 경계
- 정책 보호선: 149/150/179/180/199/200/499/500 경계
- idempotency key 안정성
- JSON encode/decode 호환성
- 상태 전이에서 금지된 역방향 전이

### iOS 실기기 테스트

1. 번호 1개, 반복 1회, 딜레이 끔
2. 번호 2개, 반복 1회
3. 번호 2개, 반복 3회
4. 고정 딜레이와 실제 도착 시간 기록
5. 랜덤 딜레이와 payload 값 비교
6. 실행 중 사용자 취소
7. 네트워크 단절/복구
8. 앱 callback 완료/취소/오류
9. 사진 1장 iMessage
10. 사진 1장 Android 수신자의 RCS/MMS
11. 사진 여러 장 iMessage/MMS/RCS
12. 일반 파일 여러 개와 사진·파일 혼합 첨부

### Android 실기기 테스트

1. SIM 없음/Wi-Fi 전용 기기 capability 차단
2. 단일 SIM과 다중 SIM 선택
3. SMS 단문/장문 분할
4. sent와 delivery callback 구분
5. 앱 종료/재부팅 후 중복 방지
6. 권한 거부/기본 SMS 역할 해제
7. MMS 데이터 꺼짐/APN 오류
8. 제조사별 백그라운드 제한

## 다음 구현 순서

1. iOS 단축어에 `plannedDelaySeconds` 추출과 `대기` 연결
2. 완료/취소/오류 callback 실기기 검증
3. iCloud 공유 단축어를 만들고 앱 설치 링크에 등록
4. 사진 1장 단축어 단위 검증 후 다중 사진·파일·혼합 첨부로 확장
5. 여러 `IntentFile`을 반환하는 `AppIntent` 첨부파일 브리지 구현
6. 캠페인별 진행/확인 필요 UI와 일·월 요청량 집계 검증
7. 공통 JSON Schema와 테스트 벡터 파일 추가
8. Android 프로토타입에서 먼저 `SmsIntentTransport` 구현
9. Play 배포 정책을 확정한 뒤 기본 SMS 앱 또는 서버 API 경로 선택

각 단계는 `docs/group-sms-test-plan.md`의 Gate를 통과한 뒤 다음 단계로 진행한다.

## 공식 참고자료

- Apple Shortcuts 변수: https://support.apple.com/ko-kr/guide/shortcuts/apdd02c2780c/9.0/ios/26
- Apple 메시지 전송 방식: https://support.apple.com/ko-kr/guide/iphone/iph82fb73ba3/ios
- Apple App Intents: https://developer.apple.com/documentation/appintents/app-intents
- Apple IntentFile: https://developer.apple.com/documentation/appintents/intentfile
- Android SmsManager: https://developer.android.com/reference/android/telephony/SmsManager
- Google Play SMS/Call Log 정책: https://support.google.com/googleplay/android-developer/answer/10208820
