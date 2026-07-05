# Customer List OCR CLI

Mac에서 스캔 이미지 파일을 Apple Vision OCR로 읽고, 행/열 형태로 복원한 뒤 CSV를 생성하는 1차 검증 도구입니다.

## 실행

```bash
cd tools/customer-list-ocr-cli
swift run customer-list-ocr /path/to/customer-list.jpg --headers "열A,열B,열C,열D"
```

기본 출력 위치:

```text
tools/customer-list-ocr-cli/ocr-output/
```

출력 파일:

- `ocr-boxes.json`: OCR 원본 텍스트와 정규화 좌표
- `table.json`: 행/열 복원 결과
- `result.csv`: PWA 가져오기 탭에서 사용할 CSV

## 옵션

```text
--out-dir <path>              출력 폴더
--headers "열A,열B,열C"          CSV 헤더. 생략하면 열1, 열2... 사용
--header-mode <auto|none>     첫 행 헤더 자동 판정. 기본값 auto
--languages "ko-KR,en-US"     OCR 언어. 기본값 ko-KR,en-US
--min-confidence <number>     낮은 신뢰도 텍스트 제외 기준. 기본값 0
--row-threshold <number>      행 묶기 기준. 촘촘한 표는 0.01~0.018 권장
--help                        도움말
```

`--headers`는 예시 필드에 고정되지 않습니다. 사용자가 원하는 임의의 열 이름을 순서대로 넣으면 됩니다.

헤더 처리 방식:

- `--headers`를 지정하면 해당 값을 CSV 첫 행으로 사용합니다.
- `--headers`를 생략하고 `--header-mode auto`이면 첫 행만 나머지 행과 형태가 다를 때 헤더로 인식합니다.
- 첫 행이 데이터와 비슷하면 첫 행도 데이터로 유지하고 `열1`, `열2`처럼 자동 헤더를 만듭니다.
- `--header-mode none`이면 첫 행 헤더 판정을 하지 않고 단순 OCR 변환 결과를 CSV로 만듭니다.

OCR CLI는 열의 의미를 해석하지 않고 셀 값을 행/열 형태로 복원하는 데만 집중합니다.

행이 여러 줄로 합쳐지면 `--row-threshold` 값을 낮춰 실행합니다.

```bash
swift run customer-list-ocr /path/to/customer-list.heic --row-threshold 0.012
```

## 개인정보 규칙

실제 고객정보가 포함된 이미지, OCR JSON, 표 복원 JSON, 결과 CSV는 Git에 커밋하지 않습니다. 실제 고객정보 샘플은 `test-data/private/` 또는 로컬 전용 폴더에만 둡니다.
