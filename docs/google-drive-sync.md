# Google Drive 동기화

## 현재 방식

앱은 사용자 데이터를 중앙 서버가 아니라 사용자의 Google Drive에 저장합니다.

```text
PWA 로컬 저장: IndexedDB
네이티브 로컬 저장: 앱 샌드박스 JSON + 고객 사진 폴더
기본 동기화: Google Drive appDataFolder
사용자 백업: 일반 Google Drive JSON 파일
```

네이티브 앱에서는 로컬 저장 원본이 앱 샌드박스입니다. 고객리스트/고객/히스토리/스케줄/템플릿은 JSON 메타데이터로 저장하고, 고객별 사진 메모, 방문 지도 스냅샷, 음성 메모 파일은 앱 내부 파일 저장소에 저장합니다. Google Drive 연결 전에는 이 데이터를 하나의 전체 백업 JSON으로 묶어 내보내고 가져옵니다.

PWA와 네이티브 앱은 데이터 구조와 사진 포함 여부가 다르므로 Drive 동기화 파일명을 분리합니다.

```text
PWA 동기화 파일: 기존 PWA sync JSON
네이티브 동기화 파일: soheega-ganda-native-sync.json
```

## 장점

- 별도 서버 비용이 없습니다.
- 사용자의 고객 데이터가 운영자 서버에 저장되지 않습니다.
- 사용자는 본인 Google 계정으로 본인 데이터를 보관합니다.
- iPhone, iPad, PC 간 같은 Google 계정으로 복원할 수 있습니다.

## Google OAuth 설정

현재 Google Auth Platform 설정:

```text
User type: External
Publishing status: In production
Authorized JavaScript origin: https://lucid47.github.io
```

GitHub Variables:

```text
VITE_GOOGLE_CLIENT_ID
```

네이티브 iOS 앱은 웹용 `VITE_GOOGLE_CLIENT_ID`를 그대로 쓰지 않습니다. PWA는 JavaScript Web OAuth Client ID를 사용하고, iPhone/iPad 네이티브 앱은 iOS application 타입의 OAuth Client ID를 별도로 사용합니다.

Google 공식 문서 기준으로 설치형 앱은 사용자의 기기 안에 배포되므로 client secret을 안전하게 숨길 수 없습니다. 따라서 iOS 앱에는 client secret을 넣지 않고, iOS OAuth Client ID와 PKCE code challenge 흐름을 사용합니다.

현재 네이티브 코드의 구현 방식:

```text
인증 화면: ASWebAuthenticationSession으로 Google OAuth 페이지 열기
OAuth 방식: Authorization Code + PKCE
Client ID: iOS application OAuth Client ID
Client Secret: 사용하지 않음
Redirect Scheme: GoogleDriveRedirectScheme
Redirect URI: {GoogleDriveRedirectScheme}:/oauth2redirect
Token 저장: refresh token은 iOS Keychain에 저장
Access token: 메모리에서 만료 전까지 재사용하고 refresh token으로 자동 갱신
계정 표시 정보 저장: 이메일/이름/사진 URL 정도만 UserDefaults에 저장
```

필요한 Google Cloud 설정:

```text
1. Google Cloud Console에서 같은 프로젝트 선택
2. Google Drive API 활성화
3. OAuth consent screen에 앱 이름, 지원 이메일, 개발자 연락처 설정
4. OAuth scope에 아래 권한 등록
5. OAuth Client 생성
   - Application type: iOS
   - Name: 소희야 가자 iOS
   - Bundle ID: com.lucid47.outboundsales
   - App Store ID: 아직 배포 전이면 비워둠
   - Team ID: App Check을 쓸 때 필요, 1차 구현에서는 선택
6. 생성된 iOS Client ID를 로컬 설정 파일에 입력하고 빌드 시 주입
```

```text
iOS Bundle ID: com.lucid47.outboundsales
기본 URL Scheme: com.lucid47.outboundsales
앱 Redirect URI: com.lucid47.outboundsales:/oauth2redirect
Info.plist 키: GoogleDriveOAuthClientID
Info.plist 키: GoogleDriveRedirectScheme
```

실제 기기 테스트 전에는 Google Cloud에서 발급한 iOS OAuth Client ID를 `native/.google-drive-oauth.local`에 넣고 자동화 스크립트로 빌드합니다. 이 값이 비어 있거나 자리표시자이면 앱의 Google Drive 연결 버튼은 동작하지 않아야 합니다.

앱에서 사용하는 권한:

```text
openid
email
profile
https://www.googleapis.com/auth/drive.appdata
https://www.googleapis.com/auth/drive.file
```

권한 사용 목적:

```text
openid/email/profile:
  연결된 Google 계정의 이름과 이메일을 설정 화면에 표시

https://www.googleapis.com/auth/drive.appdata:
  사용자가 직접 보지 않아도 되는 앱 내부 동기화 파일 저장
  네이티브 동기화 파일명: soheega-ganda-native-sync.json

https://www.googleapis.com/auth/drive.file:
  사용자가 직접 볼 수 있는 일반 Google Drive 백업 JSON 파일 생성
```

`drive.appdata`만 쓰면 앱 내부 동기화에는 충분하지만, 사용자가 눈으로 확인 가능한 백업 파일을 일반 Drive에 만들 수 없습니다. 그래서 현재 구조는 `drive.appdata`를 기본 동기화에 사용하고, `drive.file`은 사용자가 명시적으로 백업 파일을 만들 때 사용합니다.

### Info.plist 반영 기준

현재 네이티브 앱은 아래 값을 읽습니다. 실제 Client ID는 Git에 커밋하지 않고, 빌드 시 `$(GOOGLE_DRIVE_OAUTH_CLIENT_ID)`에 주입합니다.

```xml
<key>GoogleDriveOAuthClientID</key>
<string>$(GOOGLE_DRIVE_OAUTH_CLIENT_ID)</string>
<key>GoogleDriveRedirectScheme</key>
<string>$(GOOGLE_DRIVE_REDIRECT_SCHEME)</string>
```

그리고 URL scheme에도 같은 scheme이 등록되어 있어야 합니다.

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>Google Drive OAuth</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>$(GOOGLE_DRIVE_REDIRECT_SCHEME)</string>
    </array>
  </dict>
</array>
```

Google OAuth 요청에 사용되는 redirect URI는 아래 형태입니다.

```text
com.lucid47.outboundsales:/oauth2redirect
```

### 로컬 빌드 자동화

1. 예시 파일을 복사합니다.

```bash
cp native/.google-drive-oauth.local.example native/.google-drive-oauth.local
```

2. `native/.google-drive-oauth.local`에 Google Cloud에서 발급한 iOS OAuth Client ID를 넣습니다.

```text
GOOGLE_DRIVE_OAUTH_CLIENT_ID=발급받은_iOS_Client_ID.apps.googleusercontent.com
GOOGLE_DRIVE_REDIRECT_SCHEME=com.lucid47.outboundsales
```

3. 앱을 빌드합니다.

```bash
native/scripts/build-ios-with-google-drive.sh
```

Xcode의 실행 버튼이나 일반 `xcodebuild`를 사용해도 `native/GoogleDriveOAuth.xcconfig`가 Git 제외된 로컬 설정을 선택적으로 읽습니다. 따라서 같은 Mac에서는 전용 스크립트와 Xcode 직접 빌드 모두 동일한 OAuth Client ID를 포함합니다.

4. 연결된 아이폰에 바로 설치하려면 기기 ID를 넣습니다.

```bash
native/scripts/build-ios-with-google-drive.sh --device-id 기기_ID --install
```

`native/.google-drive-oauth.local`은 Git 제외 대상입니다. 실제 Client ID를 `Info.plist`에 직접 넣어 커밋하지 않습니다.

빌드 결과의 `GoogleDriveOAuthClientID`가 비어 있으면 앱은 컴파일되지만 설정 화면에 Client ID 필요 상태가 표시되고 Google 로그인을 시작할 수 없습니다.

주의:

- `GoogleDriveOAuthClientID`에는 웹용 `VITE_GOOGLE_CLIENT_ID`가 아니라 iOS application 타입 Client ID를 넣습니다.
- 네이티브 앱에는 client secret을 넣지 않습니다.
- Bundle ID와 Xcode의 `PRODUCT_BUNDLE_IDENTIFIER`가 Google Cloud에 등록한 Bundle ID와 다르면 로그인 중 `redirect_uri_mismatch` 또는 OAuth client 관련 오류가 날 수 있습니다.
- Google Sign-In SDK로 전환하는 경우에는 Google Cloud가 제공하는 reversed client ID URL scheme을 쓰는 방식이 일반적입니다. 현재 코드는 SDK 방식이 아니라 직접 OAuth+PKCE 방식이므로 `GoogleDriveRedirectScheme` 기반 custom scheme을 사용합니다.

### 구현 선택지

현재 프로젝트는 1차 구현 속도를 위해 직접 OAuth+PKCE 방식을 사용합니다.

```text
장점:
- 서버가 필요 없음
- Google Drive REST API 호출 흐름을 직접 제어 가능
- 현재 PWA의 appDataFolder 동기화 구조와 맞추기 쉬움

주의점:
- OAuth redirect URI와 URL scheme 설정을 정확히 맞춰야 함
- refresh token은 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 정책으로 Keychain에 보관
- access token은 Keychain에 장기 저장하지 않고 앱 실행 중 캐시만 사용
- Google 정책 변화가 있으면 직접 대응해야 함
```

대안은 Google Sign-In iOS SDK를 사용하는 방식입니다.

```text
장점:
- Google이 권장하는 iOS 로그인 SDK
- 로그인/계정 선택/URL scheme 설정 패턴이 명확함
- 향후 보안 정책 변화 대응이 상대적으로 쉬움

주의점:
- 기존 직접 OAuth 코드 일부를 SDK 기반으로 다시 연결해야 함
- Drive API 호출용 access token 획득 흐름을 SDK 방식에 맞춰 정리해야 함
```

결론:

```text
현재 단계: 직접 OAuth+PKCE 유지
앱스토어 배포 또는 장기 운영 단계: Google Sign-In iOS SDK 전환 검토
```

## 사용자 흐름

기존 기기 전체 동기화:

```text
설정
→ Google 계정으로 연결
→ 권한 허용
→ Drive와 동기화
```

새 기기 전체 복원:

```text
설정
→ Google 계정으로 연결
→ Drive에서 복원
→ 전체 복원 선택
→ 로컬 데이터를 Drive 데이터로 교체 복원
→ 이후 Drive와 동기화 사용
```

선택 백업:

```text
설정
→ Drive 백업 파일 만들기
→ 선택 고객리스트
→ 백업할 고객리스트 선택
→ Google Drive에 JSON 백업 파일 생성
```

선택 복원:

```text
설정
→ Drive에서 복원
→ 선택 고객리스트
→ Drive 백업에서 고객리스트 목록을 먼저 불러오기
→ 복원할 고객리스트 선택
→ 선택한 고객리스트와 관련 고객/히스토리/스케줄/사진만 병합 복원
```

일상 사용:

```text
고객 수정, 전화, 문자, 메모, 완료 처리 등 로컬 변경
→ 설정 화면에 동기화 필요 표시
→ Drive와 동기화
→ 저장된 refresh token으로 access token 자동 발급
→ 로그인 화면 없이 동기화 실행
→ 마지막 동기화 시간 갱신
```

최초 연결 또는 인증 만료:

```text
최초 연결: Google 로그인 및 권한 동의 1회
정상 사용: Keychain의 refresh token으로 조용히 인증 갱신
Google에서 권한 철회 또는 invalid_grant 반환: 연결 상태 해제 후 재연결 안내
앱의 연결 해제: Keychain refresh token과 로컬 계정 표시 정보 삭제
```

2026-07-13 이전 빌드는 이메일 등 계정 표시 정보만 저장하고 refresh token을 버렸습니다. 해당 빌드에서 업데이트한 사용자는 기존 토큰을 복구할 수 없으므로 업데이트 후 Google 계정을 한 번 다시 연결해야 합니다. 이후 정상적인 동기화에서는 로그인 화면이 반복해서 나타나지 않습니다.

## 병합 정책

- 전체 복원은 로컬 데이터를 Drive 데이터로 교체합니다.
- 선택 복원은 선택한 고객리스트에 속한 고객, 스케줄, 로그, 사진만 교체/병합합니다.
- 고객리스트, 고객, 스케줄, 로그, 템플릿은 ID 기준으로 병합합니다.
- 네이티브 사진 메모는 고객 ID와 사진 ID 기준으로 병합하고, 실제 사진 파일은 백업 payload 또는 Drive appDataFolder 파일로 함께 보관합니다.
- 방문 지도 스냅샷과 음성 메모 파일은 방문 히스토리 ID 기준으로 백업 payload에 포함합니다.
- 같은 ID가 양쪽에 있으면 더 최근 수정 시각을 우선합니다.
- 로그성 데이터는 ID 기준으로 합쳐 데이터 유실을 줄입니다.

## 현재 제한

- 삭제 동기화는 아직 완전하지 않습니다.
- 삭제 동기화를 안정화하려면 `deletedAt` 필드와 tombstone 정책이 필요합니다.
- 앱이 완전히 닫힌 상태에서 백그라운드 자동 동기화는 보장하지 않습니다.
- access token은 보안을 위해 디스크에 장기 저장하지 않으며, 앱 재실행 후 첫 Drive 작업에서 Keychain의 refresh token으로 자동 재발급합니다.
- Google 계정 권한이 철회되거나 OAuth 프로젝트가 Testing 상태에서 토큰이 만료되면 사용자가 한 번 다시 연결해야 합니다.
- 자동 동기화와 백그라운드 실행은 아직 별도 구현 항목입니다.
- 실제 Google 로그인/권한 동의 화면은 Google 정책 변경에 따라 문구가 바뀔 수 있습니다.

## 운영 참고

- OAuth 앱은 Production 상태이므로 테스트 사용자 이메일을 직접 추가하지 않아도 사용할 수 있습니다.
- 사용자가 처음 연결할 때 Google 권한 동의 화면이 표시됩니다.
- 만약 `unverified app` 화면이 보이면 OAuth 브랜딩/권한 검토가 추가로 필요할 수 있습니다.
