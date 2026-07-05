# Customer List OCR CLI

Mac에서 스캔 이미지 파일을 Apple Vision OCR로 읽고, 행/열 형태로 복원한 뒤 CSV를 생성하는 1차 검증 도구입니다.

## 실행

```bash
cd tools/customer-list-ocr-cli
swift run customer-list-ocr /path/to/customer-list.jpg --headers "고객명,연락처,주소,메모"
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
--headers "고객명,연락처,주소"   CSV 헤더. 생략하면 열1, 열2... 사용
--languages "ko-KR,en-US"     OCR 언어. 기본값 ko-KR,en-US
--min-confidence <number>     낮은 신뢰도 텍스트 제외 기준. 기본값 0
--help                        도움말
```

## 개인정보 규칙

실제 고객정보가 포함된 이미지, OCR JSON, 표 복원 JSON, 결과 CSV는 Git에 커밋하지 않습니다. 실제 고객정보 샘플은 `test-data/private/` 또는 로컬 전용 폴더에만 둡니다.
