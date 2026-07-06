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
- 가져오기 탭 하위 기능 구성
  - CSV 파일 선택 import
  - 빈 고객리스트 직접 생성
  - 대상 고객리스트를 확인/선택한 뒤 고객 수동 추가
  - 사진/OCR 가져오기 진입 영역
- Apple MapKit 기반 지도 탭
  - 좌표가 있는 고객을 지도 핀으로 표시
  - 선택 리스트 기준 지도 표시 수와 전체 고객 수 표시
- 고객 상세/수정 화면
- 전화, 문자, Apple 지도 길찾기 실행
- 템플릿 문자 클립보드 복사와 문자앱 실행
- 메모, 방문 완료, 완료/취소 히스토리 저장
- 오늘 스케줄 생성과 고객 추가/제거
- JSON 백업 내보내기/가져오기
- Apple CLGeocoder 기반 주소 좌표 변환
- CSV 텍스트 붙여넣기 import
- OCR 진입 영역 초안
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

## 로컬 데이터

네이티브 앱의 1차 로컬 저장은 앱 샌드박스의 Application Support 영역에 `native-data.json` 파일로 저장합니다. 고객정보 파일은 Git에 포함하지 않으며, 이후 실제 기기 테스트가 완료되면 iOS 백업/복원, Google Drive 동기화, 삭제 동기화 정책을 별도로 연결합니다.

## 다음 단계

- 실제 iPhone/iPad 연결 후 Xcode에서 앱 실행 확인
- 엑셀 파일(.xlsx) import 파서 연결
- OCR 실제 사진/문서 선택과 Vision OCR 연결
- Google Drive 계정 연동과 클라우드 동기화 연결
- OCR 입력 화면에 사진/문서 선택 연결
