# 네이티브 앱 개발환경 설치 및 설정 가이드

## 목적

현재 PWA 기능과 고객리스트 OCR 기능을 함께 담는 iPhone/iPad 네이티브 앱 개발을 준비한다.

개발 방향:

1. 현재 PWA는 계속 유지하고 고도화한다.
2. OCR 기능은 Mac Swift CLI에서 검증한 코어를 기반으로 iPhone/iPad 네이티브 앱으로 확장한다.
3. 네이티브 앱에서는 문서 스캔, OCR, 표 검수, CSV 생성, 고객리스트 import 흐름을 하나의 사용 경험으로 통합한다.
4. iPhone/iPad 네이티브 앱 흐름이 안정화되면 Android 확장을 검토한다.

## 기준 개발 환경

- Mac: 최신 macOS
- IDE: 최신 Xcode
- 언어/UI: Swift, SwiftUI
- iPhone/iPad 앱 최소 기준: 최신 iOS/iPadOS 우선
- OCR: Apple Vision `VNRecognizeTextRequest`
- 문서 스캔: VisionKit `VNDocumentCameraViewController`
- 현재 검증 도구: `tools/customer-list-ocr-cli`

공식 참고:

- Xcode: https://developer.apple.com/xcode/
- Xcode 시스템 요구사항: https://developer.apple.com/xcode/system-requirements/
- Apple Developer 멤버십 비교: https://developer.apple.com/support/compare-memberships/
- Vision 텍스트 인식: https://developer.apple.com/documentation/vision/recognizing-text-in-images
- VisionKit 문서 스캔: https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller

## 개발자 계정 기준

무료 Apple 계정으로 할 수 있는 일:

- Xcode 설치
- 시뮬레이터 실행
- 기본 개발/빌드
- 제한적인 실제 기기 테스트

유료 Apple Developer Program이 필요한 경우:

- TestFlight 배포
- App Store Connect 사용
- App Store 배포
- 장기적이고 안정적인 실기기 배포/테스트

Apple Developer Program은 Apple 공식 문서 기준 연 99 USD 멤버십이다.

초기 개발은 무료 계정으로 시작하고, 실제 사용자 테스트나 TestFlight가 필요해지는 시점에 유료 계정 전환을 검토한다.

## 설치 순서

### 1. macOS 업데이트

시스템 설정에서 macOS를 최신 버전으로 업데이트한다.

```text
시스템 설정 → 일반 → 소프트웨어 업데이트
```

### 2. Xcode 설치

Mac App Store 또는 Apple Developer 사이트에서 최신 Xcode를 설치한다.

설치 후 Xcode를 한 번 실행해 추가 구성요소 설치를 완료한다.

터미널에서 확인:

```bash
xcodebuild -version
swift --version
```

### 3. Command Line Tools 확인

터미널에서 아래 명령을 실행한다.

```bash
xcode-select -p
```

문제가 있으면 Xcode 경로를 지정한다.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 4. Apple ID 연결

Xcode에서 Apple ID를 연결한다.

```text
Xcode → Settings → Accounts → Apple ID 추가
```

실기기 테스트를 하려면 Signing & Capabilities에서 Team을 선택해야 한다.

## 네이티브 앱 프로젝트 생성

권장 위치:

```text
native/OutboundSalesNative/
```

초기에는 기존 PWA와 같은 repo 안에 두되, PWA 코드와 네이티브 코드를 폴더 단위로 분리한다.

Xcode에서 생성:

```text
File → New → Project → iOS App
```

권장 설정:

- Product Name: `OutboundSalesNative`
- Interface: SwiftUI
- Language: Swift
- Testing System: 기본값 사용
- Organization Identifier: 개인/회사 도메인 역순
- Bundle Identifier 예: `com.lucid47.outboundsales`

## 권장 폴더 구조

```text
native/OutboundSalesNative/
  OutboundSalesNative.xcodeproj
  OutboundSalesNative/
    App/
    Features/
      OCR/
      Customers/
      Import/
      Settings/
    Core/
      OCRCore/
      TableExtraction/
      CSV/
      Models/
    Resources/
  OutboundSalesNativeTests/

tools/customer-list-ocr-cli/
  Sources/CustomerListOCR/
```

초기에는 `tools/customer-list-ocr-cli`에서 검증한 OCR/표 복원/CSV 로직을 네이티브 앱의 `Core/`로 옮기거나, Swift Package로 분리해 공유하는 방식을 검토한다.

## 1차 네이티브 앱 기능 범위

초기 iPhone/iPad 테스트 앱은 전체 PWA 기능을 한 번에 옮기지 않는다.

1차 목표:

- 문서 스캔
- OCR 실행
- 행/열 복원
- 표 미리보기
- 셀 수정
- 열 이름 지정
- CSV 생성
- CSV 공유 또는 파일 저장

PWA 고객관리 기능 병합은 OCR 흐름이 안정화된 뒤 진행한다.

## 사용할 Apple 프레임워크

### SwiftUI

앱 화면과 상태 관리를 구현한다.

사용 예:

- 탭/내비게이션
- 문서 스캔 시작 버튼
- OCR 결과 표 미리보기
- 셀 수정 화면
- CSV 공유 화면

### VisionKit

종이 문서를 촬영하고 스캔 이미지를 얻는다.

사용 후보:

- `VNDocumentCameraViewController`

역할:

- 문서 가장자리 감지
- 촬영
- 원근 보정
- 여러 장 문서 스캔

### Vision

이미지에서 텍스트와 위치 정보를 추출한다.

사용 후보:

- `VNRecognizeTextRequest`
- `VNRecognizedTextObservation`

역할:

- 한국어/영어 OCR
- 텍스트 bounding box 추출
- Mac CLI에서 검증한 `RecognizedTextBox` 구조로 변환

### Foundation

CSV 생성, 파일 저장, 데이터 모델 처리를 담당한다.

### UniformTypeIdentifiers / ShareLink

CSV 파일을 다른 앱으로 공유하거나 파일 앱에 저장하는 흐름에 사용한다.

## 권한 설정

문서 스캔/카메라 사용을 위해 `Info.plist`에 카메라 권한 설명이 필요하다.

예:

```text
NSCameraUsageDescription
고객리스트 문서를 스캔하기 위해 카메라를 사용합니다.
```

사진 라이브러리에서 이미지를 가져오는 기능을 추가하면 사진 접근 권한도 검토한다.

## Mac CLI와 네이티브 앱의 관계

Mac CLI는 알고리즘 검증 도구다.

네이티브 앱은 아래 코어를 재사용한다.

- OCR 결과 정규화
- 행 묶기
- 열 묶기
- 헤더 자동 판정
- CSV 생성
- 회전 보정 옵션

플랫폼별로 달라지는 부분:

- Mac CLI: 이미지 파일 경로 입력, JSON/CSV 파일 출력
- iPhone/iPad 앱: 문서 스캔 입력, 표 미리보기/수정 UI, CSV 공유

## 실기기 테스트 절차

1. iPhone/iPad를 Mac에 USB로 연결한다.
2. iPhone/iPad에서 개발자 모드를 허용한다.
3. Xcode 상단 실행 대상에서 연결된 기기를 선택한다.
4. Signing & Capabilities에서 Team을 선택한다.
5. Run 버튼으로 앱을 설치한다.

실기기 테스트 중 확인할 항목:

- 문서 스캔 화면이 열리는지
- 카메라 권한 안내가 자연스러운지
- 스캔 이미지가 OCR로 전달되는지
- 표 복원이 Mac CLI 결과와 비슷한지
- CSV 공유/저장이 가능한지

## 테스트 데이터 규칙

실제 고객정보가 포함된 파일은 Git에 커밋하지 않는다.

Git 제외 대상:

- 원본 고객리스트 이미지
- 스캔 이미지
- OCR JSON
- 표 복원 JSON
- 결과 CSV
- 실제 고객정보가 포함된 앱 백업 파일

더미 데이터만 repo에 보관한다.

## 현재 권장 다음 단계

1. `native/OutboundSalesNative/`에 SwiftUI iOS 앱 프로젝트 생성
2. `tools/customer-list-ocr-cli`의 OCR/표 복원/CSV 코어를 Swift Package로 분리할지 검토
3. 네이티브 앱 1차 화면 구성
   - 문서 스캔 버튼
   - 이미지 미리보기
   - OCR 실행 버튼
   - 표 결과 미리보기
   - CSV 공유 버튼
4. Mac CLI에서 검증한 샘플 이미지와 동일한 입력으로 iPhone/iPad 결과 비교
5. OCR 기능이 안정화되면 PWA 고객리스트 import 흐름과 병합 전략 재검토

