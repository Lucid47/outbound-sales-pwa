# Native App Port

이 폴더는 기존 PWA 기능과 OCR 기능을 iPhone/iPad 네이티브 앱으로 옮기기 위한 작업 공간입니다.

## 필수 기준 문서

네이티브 앱을 기존 PWA와 같은 기능/화면으로 만들려면 아래 문서를 먼저 확인합니다.

```text
docs/native-pwa-parity-spec.md
docs/ui-reference.md
docs/feature-spec.md
docs/google-drive-sync.md
docs/customer-list-ocr.md
```

특히 UI는 SwiftUI 기본 `List` 스타일로 대체하지 말고, `docs/ui-reference.md`와 `src/App.css`를 기준으로 색상, 여백, 카드, 버튼, 하단 탭 구조를 맞춥니다.

네이티브 화면 구현 전에는 반드시 아래 PWA 원본 파일을 직접 열어 현재 구현을 확인합니다.

```text
src/App.tsx
src/App.css
src/db/appDb.ts
src/googleDriveSync.ts
```

문서와 원본 파일 사이에 차이가 있으면 원본 파일을 우선합니다. 다만 iOS 안전영역, 권한 요청, 전화/문자/지도 앱 전환, 파일/사진 선택기처럼 네이티브 플랫폼 제약이 있는 부분은 iOS 관례를 따르며, 사용 흐름과 결과만 PWA와 같게 유지합니다.

## 구조

```text
native/
  OutboundSalesCore/
    Swift Package로 분리한 공통 도메인/CSV/주소 처리 로직
  OutboundSalesNative/
    SwiftUI 화면/상태 포팅 패키지
  OutboundSalesiOS/
    iPhone/iPad에서 실행할 Xcode 앱 프로젝트
```

현재는 기존 PWA 기능을 네이티브 앱으로 옮기기 위해 공통 로직, SwiftUI 화면 모듈, iOS 앱 프로젝트를 분리해 둡니다.

## 현재 포팅된 범위

- PWA 데이터 모델의 Swift 버전
- CSV 파싱
- CSV 헤더 자동 매핑
- 현장 CSV 헤더 alias 자동 매핑
  - `우편물수령지`, `수령지`, `배송지`, `도로명주소`, `지번주소`, `휴대폰번호`, `핸드폰번호` 등 지원
- 헤더가 없거나 불명확한 CSV의 수동 컬럼 매핑
  - `첫 행을 헤더로 사용`을 끄면 `열1`, `열2`, `열3` 기준으로 고객명/연락처/주소 등을 직접 지정
- CSV 행을 `Customer` 모델로 변환
- 전화번호 정리
- 생년월일 정규화
- 주소 정규화와 지역 추출
- 지도 검색용 도로명주소 정규화
- SwiftUI 탭 구조 초안
- 고객리스트/고객 목록 화면 초안
- 가져오기 탭 하위 기능 구성
  - CSV 파일 선택 import
  - 빈 고객리스트 직접 생성
  - 대상 고객리스트를 확인/선택한 뒤 고객 수동 추가
  - iOS 연락처에서 고객 가져오기
    - 개별 연락처 선택
    - 연락처 그룹 선택
    - 새 고객리스트 생성 또는 기존 고객리스트에 추가
    - 전화번호 기준 중복 건너뛰기
  - 사진/OCR 가져오기 진입 영역
- Apple MapKit 기반 지도 탭
  - 좌표가 있는 고객을 고객명/완료 상태 라벨로 표시
  - 라벨 선택 시 주소, 스케줄 상태, 전화, 문자, 메모, 길찾기, 이력, 완료/취소, 스케줄 추가 팝업 표시
  - 선택 리스트 기준 지도 표시 수와 전체 고객 수 표시
- PWA와 같은 5개 하단 탭 구조
  - 지도는 별도 탭이 아니라 오늘/고객 화면 안의 하위 화면으로 진입
- 고객 탭 카드형/목록형 빠른 조작 UI
  - 고객 카드에서 전화, 문자, 길찾기, 스케줄, 완료를 바로 실행
  - 고객 카드에서 수정 화면을 바로 실행
  - 목록형은 빠른 스크롤을 위한 슬림 텍스트 행으로 표시
  - 선택 고객리스트 변경, 미방문/완료/전체 필터, 검색 지원
- 고객 상세/수정 화면
- 전화, 문자, 티맵 우선 길찾기와 Apple 지도 fallback 실행
- 템플릿 문자 클립보드 복사와 문자앱 실행
- 메모, 방문 완료, 완료/취소 히스토리 저장
- 오늘 스케줄 생성과 고객 추가/제거
- 기록 탭의 고객별 히스토리 목록과 고객별 전체 이력 시트
- 방문 히스토리
  - 고객카드/지도 팝업의 `방문` 버튼
  - 빠른 방문 시 현재 위치의 역변환 주소와 지도 스냅샷 저장
  - 텍스트 메모, 사진 메모, 음성 메모
  - 음성 메모 저장 후 Apple Speech 기반 전사 상태 갱신
- 설정 탭의 문자 템플릿 추가/수정/삭제
- JSON 백업 내보내기/가져오기
- Google Drive 동기화/백업
  - Google Drive appDataFolder에 네이티브 전용 전체 동기화 파일 저장/복원
  - 전체 일괄 백업/복원
  - 고객리스트별 선택 백업/복원
  - 고객리스트/고객/히스토리/스케줄/문자 템플릿/사진 메모, 방문 지도 스냅샷, 음성 메모 파일을 백업에 포함
  - 일반 Google Drive 백업 파일 생성 지원
- Apple CLGeocoder 기반 주소 좌표 변환
  - CSV import, 수동 추가, 주소 수정, 앱 시작 시 기존 미변환 고객을 좌표 변환
  - 원본 주소, 도로명 정규화 주소, 보강 주소를 순차 시도
- CSV 텍스트 붙여넣기 import
  - CSV 분석 후 저장 전 컬럼 매핑 확인
- Apple Vision 기반 사진 OCR import
  - Swift CLI에서 검증한 OCR 표 복원 코어 로직을 `OutboundSalesCore`로 이동
  - iPhone/iPad에서 카메라 촬영 또는 사진앱 선택, 표 OCR, CSV 미리보기/수정, 컬럼 매핑 확인, 고객리스트 저장 흐름 연결
- 문자 템플릿 선택 시트
  - 고객 카드, 고객 상세, 지도 팝업의 문자 버튼은 먼저 일반 문자/템플릿 문자 선택 화면을 표시
  - 템플릿 문자는 iOS 문자 작성창에 수신번호와 본문을 자동 입력
  - 문자 작성/발송이 불가능한 환경에서는 본문을 클립보드에 복사하고 문자 URL을 여는 fallback 사용
- iPhone/iPad용 Xcode 앱 프로젝트 초안
- 앱 시작 화면과 SwiftUI 루트 화면 연결
- 고객리스트/고객 데이터를 앱 전용 JSON 파일로 로컬 저장
- 앱 재실행 시 저장된 데이터 자동 복원
- 설정 화면에서 로컬 저장 상태 표시와 초기화 지원

## 빌드

```bash
cd native/OutboundSalesCore
swift build
```

SwiftUI 포팅 패키지 빌드:

```bash
cd native/OutboundSalesNative
swift build
```

iPhone/iPad 앱 프로젝트 빌드:

```bash
xcodebuild -project native/OutboundSalesiOS/OutboundSalesiOS.xcodeproj \
  -scheme OutboundSalesiOS \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

코드 서명을 끈 빌드는 설치 가능한 최종 배포본이 아니라, 아이폰용 앱 코드가 컴파일되는지 확인하는 검증용입니다. 실제 기기에 설치하려면 Xcode에서 Apple ID/Team 설정을 연결해야 합니다.

테스트는 Xcode 설치와 Command Line Tools 설정이 완료된 뒤 실행합니다.

```bash
swift test
```

## Xcode에서 열기

```bash
open native/OutboundSalesiOS/OutboundSalesiOS.xcodeproj
```

Xcode에서 `OutboundSalesiOS` scheme을 선택하면 됩니다. 현재 iOS 시뮬레이터 런타임은 설치되어 있지 않으므로 화면 실행 검증은 실제 기기 연결 또는 시뮬레이터 추가 설치 후 진행합니다.

## 로컬 데이터와 Google Drive

네이티브 앱의 1차 로컬 저장은 앱 샌드박스의 Application Support 영역에 보관합니다. 고객리스트/고객/히스토리/스케줄/템플릿 메타데이터는 `native-data.json` 파일에 저장하고, 고객별 사진 기록은 같은 앱 저장소의 `customer-photos/` 폴더에 저장합니다. 고객정보 파일과 사진 파일은 Git에 포함하지 않습니다.

Google Drive 동기화 코드는 네이티브 앱에 구현되어 있습니다. 다만 PWA의 웹 OAuth Client ID를 그대로 사용할 수 없으므로, 실제 Google 로그인/동기화 테스트 전에는 Google Cloud에서 iOS OAuth Client ID를 발급하고 아래 값을 설정해야 합니다.

```text
Bundle ID: com.lucid47.outboundsales
Redirect URI: com.lucid47.outboundsales:/oauth2redirect
Info.plist: GoogleDriveOAuthClientID
Info.plist: GoogleDriveRedirectScheme
```

Google Cloud에서는 OAuth Client를 만들 때 application type을 `iOS`로 선택합니다. 웹용 Client ID나 PWA의 `VITE_GOOGLE_CLIENT_ID`를 네이티브 앱에 넣지 않습니다.

현재 네이티브 구현은 Google Sign-In SDK가 아니라 `ASWebAuthenticationSession` + Authorization Code + PKCE 방식입니다. 따라서 client secret은 앱에 넣지 않으며, `GoogleDriveOAuthClientID`에는 iOS Client ID만 넣습니다. 실제 Client ID는 추적 파일에 직접 적지 않고 `native/.google-drive-oauth.local`에서 빌드 시 주입합니다.

```bash
cp native/.google-drive-oauth.local.example native/.google-drive-oauth.local
native/scripts/build-ios-with-google-drive.sh
```

실제 기기에 바로 설치하려면 연결된 기기 ID를 지정합니다.

```bash
native/scripts/build-ios-with-google-drive.sh --device-id 기기_ID --install
```

URL scheme은 `Info.plist`의 `CFBundleURLTypes`와 `GoogleDriveRedirectScheme`이 서로 같아야 합니다.

필요 scope는 아래와 같습니다.

```text
openid
email
profile
https://www.googleapis.com/auth/drive.appdata
https://www.googleapis.com/auth/drive.file
```

Google Drive 기본 동기화는 appDataFolder의 `soheega-ganda-native-sync.json` 파일을 사용합니다. 사용자가 직접 확인 가능한 백업 파일은 일반 Drive JSON 파일로 별도 생성합니다.

## 다음 단계

- 실제 iPhone/iPad 연결 후 전화/문자/티맵/Apple 지도 앱 전환 확인
- 엑셀 파일(.xlsx) import 파서 연결
- OCR 실제 사진 품질별 반복 테스트와 컬럼 매핑 UI 고도화
- Google Cloud iOS OAuth Client ID 발급 후 실제 Google Drive 로그인/동기화 테스트
