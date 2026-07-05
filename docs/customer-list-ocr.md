# 고객리스트 OCR 개발 계획

## 목표

스캔 이미지 파일을 입력받아 인쇄된 고객리스트의 각 셀 값을 OCR로 읽고, 행/열 형태로 복원한 뒤, 사용자가 각 열의 의미를 지정해서 CSV 파일로 저장한다.

원본 표와 완전히 동일한 디자인을 복원하는 것이 아니라, 업무에 사용할 수 있는 행/열 데이터로 변환하는 것이 목적이다.

## 1차 개발 범위: Mac Swift CLI 검증

1차 개발은 현재 PWA 안에 바로 넣는 기능이 아니라, Apple Vision을 호출할 수 있는 별도 Mac 검증 도구로 진행한다. 현재 PWA는 브라우저 기반이므로 Apple Vision, VisionKit 같은 네이티브 프레임워크를 직접 호출할 수 없다.

Mac 검증 도구는 Swift CLI로 먼저 구현한다. 1차 목표는 UI가 아니라 OCR 정확도, 좌표 정규화, 행/열 복원, CSV 생성 품질을 빠르게 검증하는 것이다. 결과물은 CSV 파일이며, 생성된 CSV는 기존 PWA의 고객리스트 import 기능으로 가져온다.

- 스캔 이미지 파일 입력
- Apple Vision 기반 OCR 실행
- OCR 결과를 텍스트와 위치값으로 추출
- y좌표 기준 행 묶기
- x좌표 기준 열 묶기
- 셀 단위 표 데이터 생성
- JSON/CSV 파일로 결과 확인
- CLI 옵션으로 각 열 이름 지정
  - 예: 1열 = 고객명, 2열 = 연락처, 3열 = 주소, 4열 = 메모
- CSV 파일 생성 및 저장

## 현재 구현 위치

1차 Swift CLI는 아래 경로에 둔다.

```text
tools/customer-list-ocr-cli/
```

실행 예:

```bash
cd tools/customer-list-ocr-cli
swift run customer-list-ocr /path/to/customer-list.jpg --headers "고객명,연락처,주소,메모"
```

현재 CLI 출력:

- `ocr-boxes.json`: OCR 원본 텍스트와 정규화 좌표
- `table.json`: 행/열 복원 결과
- `summary.json`: 실행 요약
- `result.csv`: PWA 가져오기 탭에서 사용할 CSV

## 1차 산출물

- Mac에서 실행 가능한 Swift CLI OCR 검증 도구
- 입력:
  - 이미지 파일 1장
  - 지원 우선순위: `.jpg`, `.jpeg`, `.png`, `.heic`
- 출력:
  - OCR 원본 결과 JSON
  - 행/열 복원 결과 JSON
  - 사용자가 지정한 헤더가 적용된 CSV
- UI:
  - 1차 CLI에는 GUI를 넣지 않는다.
  - 결과 확인은 JSON/CSV 파일로 한다.
  - 표 미리보기, 셀 수정, 열 이름 지정 UI는 2차 SwiftUI Mac 앱에서 구현한다.

## 현재 PWA와의 관계

- OCR 기능은 기존 CSV import를 대체하지 않고, CSV import 앞단의 보조 변환 도구로 둔다.
- 1차 검증 도구가 생성한 CSV는 현재 `가져오기` 탭에서 그대로 import할 수 있어야 한다.
- OCR 결과가 안정화되면 이후 선택지는 두 가지다.
  - Mac/iPhone/Android 네이티브 앱으로 OCR 기능을 분리 유지
  - PWA에는 "OCR로 만든 CSV 가져오기" 안내와 import 편의 기능만 추가

## 단계별 통합 전략

1. PWA 고도화 유지
   - 현재 PWA는 운영 가능한 고객관리 도구로 계속 개선한다.
   - CSV import, 고객관리, 전화/문자/길찾기, 기록, Google Drive 동기화 안정성을 우선 유지한다.
2. OCR 기능 분리 개발
   - OCR은 별도 Mac 검증 도구로 먼저 구현한다.
   - 이 단계에서는 Apple Vision OCR 정확도, 행/열 복원 품질, CSV 생성 품질 검증에 집중한다.
3. CSV 기반 연결
   - OCR 도구가 생성한 CSV를 기존 PWA `가져오기` 탭에서 import한다.
   - 이 방식으로 PWA 본체를 흔들지 않고 OCR 실효성을 검증한다.
4. PWA 병합 검토
   - OCR 기능이 안정화되면 PWA 안에서 OCR 기반 import를 안내하거나 연결하는 흐름을 검토한다.
   - 브라우저에서 네이티브 OCR을 직접 호출할 수 없으므로, 직접 병합이 아니라 OCR 도구와 PWA import를 매끄럽게 연결하는 방식도 병합 후보로 본다.
5. 네이티브 앱 전환 판단
   - 문서 스캔, OCR, 표 검수 경험이 제품의 핵심이 되면 iPhone/iPad 네이티브 앱 전환을 검토한다.
   - 네이티브 전환 시 PWA의 고객관리 기능을 함께 옮길지, OCR 전용 앱으로 유지할지 별도 판단한다.
6. Android 확장
   - iPhone/iPad 네이티브 앱 흐름이 검증되면 Android 확장을 검토한다.
   - Android OCR과 문서 스캔은 ML Kit을 사용하고, 표 복원과 CSV 생성 로직은 가능한 공통 구조를 유지한다.

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

1. Swift CLI
   - 이미지 파일 입력
   - Vision OCR
   - 좌표 포함 OCR JSON 저장
   - 표 복원 JSON 저장
   - CSV 생성
2. SwiftUI Mac 앱
   - CLI에서 검증한 OCR/표 복원 코어 재사용
   - 이미지 파일 선택
   - 표 미리보기
   - 셀 수정
   - 열 이름 지정
   - CSV 저장

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

## 개발 환경 기준

- 최신 macOS 기준으로 개발한다.
- 최신 Xcode 기준으로 개발한다.
- iPhone/iPad 확장 시 최신 iOS/iPadOS 기준으로 개발한다.
- OCR 언어 지원은 실행 환경에서 Apple Vision의 지원 언어 목록을 확인해 검증한다.
- 하위 OS 호환성은 1차 목표에 포함하지 않는다.

## 공통 데이터 구조

플랫폼별 OCR 결과는 아래와 같은 공통 구조로 변환한다.

```ts
RecognizedTextBox
{
  text: string
  x: number
  y: number
  width: number
  height: number
  confidence: number | null
  sourceLevel: "block" | "line" | "word"
}
```

좌표는 플랫폼과 이미지 크기에 상관없이 비교할 수 있도록 0~1 정규화 좌표로 저장한다. 원점은 좌상단 기준으로 통일한다.

표 복원 결과는 아래 구조를 목표로 한다.

```ts
OcrTable
{
  rows: OcrCell[][]
  columnCount: number
  warnings: string[]
}

OcrCell
{
  text: string
  boxes: RecognizedTextBox[]
  rowIndex: number
  columnIndex: number
  confidence: number | null
}
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

## 표 복원 알고리즘 초안

1. OCR 결과 정규화
   - Vision 결과의 bounding box를 좌상단 기준 0~1 좌표로 변환한다.
   - 공백만 있는 텍스트와 신뢰도가 너무 낮은 텍스트는 제거 후보로 표시한다.
2. 행 묶기
   - 각 텍스트 박스의 세로 중심값을 기준으로 가까운 항목끼리 같은 행으로 묶는다.
   - 기준값은 평균 글자 높이 또는 행 높이의 일정 비율로 시작한다.
   - 행 안에서는 x좌표 오름차순으로 정렬한다.
3. 열 후보 추정
   - 전체 텍스트 박스의 x좌표 분포를 기준으로 열 중심 후보를 만든다.
   - 행마다 항목 개수가 조금 달라도 전체에서 반복되는 x좌표 위치를 우선한다.
4. 셀 배치
   - 각 행의 텍스트 박스를 가장 가까운 열 후보에 배치한다.
   - 같은 행/열에 여러 박스가 들어오면 공백 또는 줄바꿈으로 합친다.
5. 빈 셀 처리
   - 해당 행에 특정 열 값이 없으면 빈 문자열로 둔다.
   - CSV 컬럼 수는 사용자가 확정한 열 수 또는 추정된 최대 열 수를 따른다.
6. 검수 경고
   - 열 수가 다른 행
   - 너무 긴 셀
   - 신뢰도 낮은 셀
   - 같은 열에 겹쳐 들어온 텍스트
   - 행으로 묶이지 못한 텍스트

## 사용자 확인 흐름

1. 사용자가 스캔 이미지 파일을 선택한다.
2. OCR을 실행한다.
3. 복원된 표를 보여준다.
4. 사용자가 필요한 경우 셀 값을 수정한다.
5. 사용자가 열 이름을 지정한다.
6. 미사용 열은 제외할 수 있다.
7. CSV를 저장한다.
8. 저장된 CSV를 기존 PWA의 `가져오기` 탭에서 import한다.

## CSV 생성 규칙

- 첫 행은 사용자가 지정한 열 이름을 사용한다.
- 열 이름이 비어 있는 열은 기본값 `열1`, `열2`처럼 표시하거나 제외 선택을 제공한다.
- 셀 안의 줄바꿈, 쉼표, 큰따옴표는 CSV 규칙에 맞게 이스케이프한다.
- UTF-8 인코딩을 기본으로 한다.
- 기존 PWA import가 인식하는 필드명을 우선 추천한다.
  - 고객명
  - 연락처
  - 주소
  - 생년월일
  - 메모
  - 위도
  - 경도

## 검증용 샘플 기준

초기 검증에는 실제 고객정보가 아닌 더미 데이터 이미지를 사용한다. 실제 고객정보 이미지로 테스트할 때는 로컬에서만 처리하고, GitHub에 원본 이미지나 OCR 결과를 올리지 않는다.

권장 샘플:

- 표 선이 있는 인쇄물
- 표 선이 없고 간격만 있는 리스트
- 헤더가 있는 이미지
- 헤더가 없는 이미지
- 주소나 메모가 긴 이미지
- 일부 빈 셀이 있는 이미지
- 살짝 기울어진 촬영 이미지

## 확정된 구현 순서

1. Swift CLI
   - UI 없이 이미지 파일을 입력받는다.
   - OCR 결과, 표 복원 결과, CSV 결과를 파일로 저장한다.
   - 실패 원인을 단계별 JSON으로 확인할 수 있게 한다.
2. SwiftUI Mac 앱
   - CLI에서 검증한 코어를 재사용한다.
   - 표 미리보기, 셀 수정, 열 이름 지정, CSV 저장 UX를 구현한다.
3. iPhone/iPad 네이티브 확장
   - VisionKit 문서 스캔으로 이미지 입력을 대체한다.
   - Apple Vision OCR과 표 복원 코어를 재사용한다.
4. PWA 연결
   - OCR로 생성한 CSV가 기존 PWA `가져오기` 탭에서 안정적으로 import되도록 한다.

## 보안 및 테스트 데이터 규칙

- 실제 고객정보가 포함된 이미지, OCR JSON, 표 복원 JSON, 결과 CSV는 Git에 커밋하지 않는다.
- Git에는 더미 샘플, 문서, 코드만 저장한다.
- 실제 고객정보 파일은 로컬 테스트 폴더에만 둔다.
- 필요한 경우 테스트 폴더와 출력 폴더를 `.gitignore`에 추가한다.

## 권장 개발 순서

1. 더미 고객리스트 이미지 샘플 준비
2. Swift CLI 프로젝트 구성
3. 이미지 파일 입력 기능 구현
4. Apple Vision OCR 결과를 좌표 포함 JSON으로 저장
5. 좌표 정규화 데이터 구조 구현
6. 행 묶기 알고리즘 구현
7. 열 묶기 알고리즘 구현
8. 셀 배열 생성
9. CSV 생성 함수 구현
10. 기존 PWA CSV import로 결과 CSV 검증
11. SwiftUI Mac 앱 프로젝트 구성
12. 표 미리보기 UI 구현
13. 셀 수정 UI 구현
14. 열 이름 지정 UI 구현
15. 실제 고객리스트 샘플 이미지로 정확도 개선
16. iPhone/iPad 문서 스캔 입력으로 확장
17. Android ML Kit OCR 입력으로 확장

## 성공 기준

- 인쇄된 고객리스트 이미지에서 각 셀의 텍스트를 읽을 수 있다.
- 표 형태가 원본과 완벽히 같지 않아도 행/열 데이터로 사용할 수 있다.
- 사용자가 열 이름을 지정해 CSV 헤더를 만들 수 있다.
- 최종 CSV를 업무에 사용할 수 있다.
- OCR로 생성한 CSV가 기존 PWA `가져오기` 탭에서 정상 import된다.

## 1차 구현 완료 기준

- 더미 이미지 3종 이상에서 OCR 결과 JSON이 생성된다.
- 표 선이 있는 샘플에서 행/열 복원 결과가 눈으로 검수 가능한 수준으로 나온다.
- 사용자가 지정한 열 이름으로 CSV가 저장된다.
- 저장된 CSV를 PWA에서 import했을 때 고객명, 연락처, 주소, 메모가 정상 표시된다.
- 고객정보가 포함된 테스트 파일은 Git 추적 대상에서 제외된다.
