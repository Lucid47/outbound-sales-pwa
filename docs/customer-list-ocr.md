# 고객리스트 OCR 개발 계획

## 목표

스캔 이미지 파일을 입력받아 인쇄된 고객리스트의 각 셀 값을 OCR로 읽고, 행/열 형태로 복원한 뒤, 사용자가 각 열의 의미를 지정해서 CSV 파일로 저장한다.

원본 표와 완전히 동일한 디자인을 복원하는 것이 아니라, 업무에 사용할 수 있는 행/열 데이터로 변환하는 것이 목적이다.

## 1차 개발 범위: Mac 코어 검증

- 스캔 이미지 파일 입력
- Apple Vision 기반 OCR 실행
- OCR 결과를 텍스트와 위치값으로 추출
- y좌표 기준 행 묶기
- x좌표 기준 열 묶기
- 셀 단위 표 데이터 생성
- 표 미리보기
- 사용자가 각 열 이름 지정
  - 예: 1열 = 고객명, 2열 = 연락처, 3열 = 주소, 4열 = 메모
- CSV 파일 생성 및 저장

## 제외 범위

- 열 의미 자동 추론
- 고객명/연락처/주소 자동 분류
- App Store 배포
- Android 앱 배포
- 실시간 카메라 OCR
- 완벽한 원본 표 디자인 복원

## 참조 프로젝트

- GitHub: https://github.com/truth0530/autoOCR

참조할 부분:

- Apple Vision OCR 사용 방식
- 한국어/영어 인식 언어 지정
- CoreImage 기반 이미지 전처리
- OCR 결과 정렬 방식
- 로컬 처리 중심 구조

참조하지 않을 부분:

- macOS 화면 캡처
- 메뉴바 앱
- 전역 단축키
- 자막 누적
- 클립보드 자동 복사
- 실시간 반복 인식

## Apple 플랫폼 방향

Mac 검증 단계:

- 이미지 파일 입력
- Vision OCR
- 표 복원
- CSV 생성

iPhone/iPad 확장 단계:

- 문서 스캔: VisionKit `VNDocumentCameraViewController`
- OCR: Apple Vision `VNRecognizeTextRequest`
- 표 복원과 CSV 생성은 Mac에서 검증한 코어 로직을 재사용

## Android 플랫폼 방향

Android 확장 단계:

- 문서 스캔: Google ML Kit Document Scanner
- OCR: Google ML Kit Text Recognition v2
- OCR 결과를 공통 데이터 구조로 변환
- 표 복원과 CSV 생성은 공통 로직으로 처리

주의:

- Android 문서 스캔 기능은 Google Play services 의존성이 있다.
- Google Play services가 없는 일부 기기에서는 제한될 수 있다.

## 공통 데이터 구조

플랫폼별 OCR 결과는 아래와 같은 공통 구조로 변환한다.

```text
RecognizedTextBox
- text
- x
- y
- width
- height
- confidence
- sourceLevel
```

이후 공통 흐름:

```text
RecognizedTextBox[]
→ 행 묶기
→ 열 묶기
→ 셀 배열 생성
→ 사용자 열 이름 적용
→ CSV 생성
```

## 권장 개발 순서

1. Mac에서 이미지 파일 입력 기능 구현
2. Apple Vision OCR 결과를 좌표 포함 JSON 또는 디버그 화면으로 확인
3. 행 묶기 알고리즘 구현
4. 열 묶기 알고리즘 구현
5. 셀 배열 생성
6. 표 미리보기 UI 구현
7. 열 이름 지정 UI 구현
8. CSV 저장 구현
9. 실제 고객리스트 샘플 이미지로 정확도 개선
10. iPhone/iPad 문서 스캔 입력으로 확장
11. Android ML Kit OCR 입력으로 확장

## 성공 기준

- 인쇄된 고객리스트 이미지에서 각 셀의 텍스트를 읽을 수 있다.
- 표 형태가 원본과 완벽히 같지 않아도 행/열 데이터로 사용할 수 있다.
- 사용자가 열 이름을 지정해 CSV 헤더를 만들 수 있다.
- 최종 CSV를 업무에 사용할 수 있다.

