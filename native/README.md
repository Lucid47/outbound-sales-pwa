# Native App Port

이 폴더는 기존 PWA 기능과 OCR 기능을 iPhone/iPad 네이티브 앱으로 옮기기 위한 작업 공간입니다.

## 구조

```text
native/
  OutboundSalesCore/
    Swift Package로 분리한 공통 도메인/CSV/주소 처리 로직
  OutboundSalesNative/
    추후 Xcode에서 생성할 SwiftUI iOS 앱 프로젝트
```

현재는 Xcode 설치 완료 전에도 개발 가능한 `OutboundSalesCore`부터 포팅합니다. Xcode 설치 후 SwiftUI 앱 프로젝트를 만들고 이 패키지를 연결합니다.

## 현재 포팅된 범위

- PWA 데이터 모델의 Swift 버전
- CSV 파싱
- CSV 헤더 자동 매핑
- CSV 행을 `Customer` 모델로 변환
- 전화번호 정리
- 생년월일 정규화
- 주소 정규화와 지역 추출
- 지도 검색용 도로명주소 정규화

## 빌드

```bash
cd native/OutboundSalesCore
swift build
```

테스트는 Xcode 설치와 Command Line Tools 설정이 완료된 뒤 실행합니다.

```bash
swift test
```
