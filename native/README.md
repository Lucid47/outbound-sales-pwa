# Native App Port

이 폴더는 기존 PWA 기능과 OCR 기능을 iPhone/iPad 네이티브 앱으로 옮기기 위한 작업 공간입니다.

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
- CSV 행을 `Customer` 모델로 변환
- 전화번호 정리
- 생년월일 정규화
- 주소 정규화와 지역 추출
- 지도 검색용 도로명주소 정규화
- SwiftUI 탭 구조 초안
- 고객리스트/고객 목록 화면 초안
- CSV 텍스트 import 화면 초안
- OCR 진입 화면 초안
- iPhone/iPad용 Xcode 앱 프로젝트 초안
- 앱 시작 화면과 SwiftUI 루트 화면 연결

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
