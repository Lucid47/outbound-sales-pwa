# SoheeGroupSMS 단축어 설계

## 목적

`SoheeGroupSMS`는 `소희가 간다` 앱이 만든 단체문자 payload를 읽어, 여러 고객에게 단톡방을 만들지 않고 1명씩 순차적으로 문자 발송을 요청하는 iOS Shortcuts 단축어다.

앱은 다음을 담당한다.

- 테스트 번호 또는 고객 목록 생성
- 메시지 본문 생성
- 순번/반복/개인화 치환
- 딜레이 계산
- JSON payload를 클립보드에 저장
- `shortcuts://x-callback-url/run-shortcut`으로 단축어 실행

단축어는 다음을 담당한다.

- 클립보드 JSON 읽기
- recipients 배열 반복
- 각 수신자 1명에게 메시지 보내기
- 항목별 plannedDelaySeconds 만큼 대기
- 완료 후 앱 callback URL 열기

## 기본 정보

- 단축어 이름: `SoheeGroupSMS`
- 단축어 버전: `0.1`
- 입력 방식: 클립보드 JSON
- 실행 방식: 앱에서 URL Scheme으로 실행
- 앱 callback scheme: `com.lucid47.outboundsales`

앱 실행 URL 예:

```text
shortcuts://x-callback-url/run-shortcut?name=SoheeGroupSMS&input=clipboard&x-success=com.lucid47.outboundsales:/group-sms/complete?campaignId=...
```

## Payload 형식

앱이 클립보드에 저장하는 JSON 구조:

```json
{
  "campaignId": "campaign-uuid",
  "campaignTitle": "반복 테스트",
  "callbackScheme": "com.lucid47.outboundsales",
  "successPath": "/group-sms/complete",
  "cancelPath": "/group-sms/cancel",
  "errorPath": "/group-sms/error",
  "createdAt": "2026-07-09T00:00:00Z",
  "recipients": [
    {
      "id": "recipient-uuid",
      "customerId": null,
      "displayName": "테스트 1",
      "phoneNumber": "01012345678",
      "messageBody": "소희가 간다 단체문자 테스트 001/010",
      "orderIndex": 0,
      "plannedDelaySeconds": 0
    }
  ]
}
```

필수 필드:

- `campaignId`
- `callbackScheme`
- `successPath`
- `errorPath`
- `recipients`
- recipient의 `phoneNumber`
- recipient의 `messageBody`
- recipient의 `plannedDelaySeconds`

## 단축어 액션 설계

Shortcuts 앱에서 아래 순서로 액션을 구성한다.

### 1. 클립보드 읽기

액션:

```text
클립보드 가져오기
```

결과:

- 변수명 추천: `PayloadText`

검증:

- `PayloadText`가 비어 있으면 오류 callback을 열고 종료한다.

### 2. JSON을 딕셔너리로 변환

액션:

```text
입력에서 딕셔너리 가져오기
```

또는 iOS 버전에 따라:

```text
JSON에서 딕셔너리 가져오기
```

입력:

- `PayloadText`

결과:

- 변수명 추천: `Payload`

### 3. payload 기본값 추출

액션:

```text
딕셔너리 값 가져오기
```

추출할 키:

- `campaignId` → `CampaignId`
- `callbackScheme` → `CallbackScheme`
- `successPath` → `SuccessPath`
- `errorPath` → `ErrorPath`
- `recipients` → `Recipients`

### 4. 수신자 반복

액션:

```text
각 항목 반복
```

반복 대상:

- `Recipients`

반복 안에서 현재 항목:

- `Repeat Item`

### 5. recipient 필드 추출

반복 안에서 `딕셔너리 값 가져오기` 액션을 사용한다.

추출할 키:

- `phoneNumber` → `PhoneNumber`
- `messageBody` → `MessageBody`
- `plannedDelaySeconds` → `DelaySeconds`

### 6. 메시지 보내기

액션:

```text
메시지 보내기
```

설정:

- 메시지: `MessageBody`
- 수신자: `PhoneNumber`
- 수신자는 항상 1명만 지정
- `Show When Run` 또는 실행 시 표시 옵션이 있으면 꺼짐으로 설정

주의:

- iOS/Shortcuts 버전에 따라 최초 실행 시 메시지 전송 권한 확인이 뜰 수 있다.
- 사용자가 단축어 권한을 허용하지 않으면 자동 발송처럼 동작하지 않을 수 있다.
- 여러 번호를 한 번에 넣으면 그룹 메시지가 될 수 있으므로 반드시 1명씩 반복한다.

### 7. 딜레이 적용

조건:

```text
DelaySeconds > 0
```

액션:

```text
대기
```

대기 시간:

- `DelaySeconds`초

주의:

- 앱에서 딜레이를 꺼도 Shortcuts와 메시지앱 자체 처리 시간이 발생할 수 있다.
- `plannedDelaySeconds`는 다음 발송 전 대기 시간으로 해석한다.

### 8. 완료 callback 열기

반복이 모두 끝난 뒤 URL 텍스트를 만든다.

형식:

```text
com.lucid47.outboundsales:/group-sms/complete?campaignId={CampaignId}
```

액션:

```text
URL 열기
```

URL:

- 위에서 만든 완료 callback URL

## 오류 callback 설계

Shortcuts는 일반 프로그래밍 언어처럼 세밀한 예외 처리가 어렵다. 1차 버전에서는 다음 정도만 처리한다.

### 클립보드가 비어 있는 경우

URL:

```text
com.lucid47.outboundsales:/group-sms/error?campaignId=unknown&reason=emptyClipboard
```

액션:

```text
URL 열기
```

그 후:

```text
단축어 중단
```

### recipients가 비어 있는 경우

URL:

```text
com.lucid47.outboundsales:/group-sms/error?campaignId={CampaignId}&reason=emptyRecipients
```

그 후 단축어를 중단한다.

## 테스트 순서

1. 앱의 `단체문자` 탭에서 테스트 번호 1개 또는 2개 입력
2. 번호당 반복 횟수 1~3회로 시작
3. 딜레이는 `꺼짐`으로 시작
4. `payload만 클립보드에 복사`
5. Shortcuts 앱에서 `SoheeGroupSMS`를 수동 실행
6. 정상 작동 확인 후 앱에서 `클립보드에 payload 저장 후 단축어 실행`
7. 5건, 10건, 30건 순서로 늘려 테스트

권장 최초 테스트:

```text
수신번호: 사용자의 보조 번호 1개
반복 횟수: 1
본문: 소희가 간다 테스트 {순번}/{전체}
딜레이: 꺼짐
```

## 성공 기준

- 단축어가 클립보드 payload를 읽는다.
- 각 메시지가 1명 수신자로만 생성된다.
- `{순번}`이 들어간 메시지가 순서대로 도착한다.
- 딜레이 `꺼짐`일 때 앱 payload의 `plannedDelaySeconds`가 0으로 전달된다.
- 딜레이 `랜덤`일 때 각 항목의 대기 시간이 달라진다.
- 완료 후 앱으로 돌아오거나 callback URL이 호출된다.

## 알려진 제약

- 앱은 실제 통신사 발송 성공 여부를 직접 알 수 없다.
- callback은 “단축어 실행 흐름이 끝났다”는 의미이지 “SMS 도달 성공” 보장이 아니다.
- iOS/Shortcuts 권한 상태에 따라 메시지 전송 전에 사용자 확인이 필요할 수 있다.
- 사용자가 단축어를 수정하거나 삭제하면 앱의 설치 확인 상태와 실제 상태가 달라질 수 있다.
- 단축어 iCloud 공유 링크는 단축어를 수정한 뒤 다시 만들어야 최신 버전이 공유된다.
