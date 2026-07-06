# UI 재현 기준

이 문서는 현재 PWA 인터페이스를 네이티브 앱에서 최대한 동일하게 재현하기 위한 시각 기준입니다.

정확한 원본은 `src/App.css`와 `src/App.tsx`입니다. 이 문서는 네이티브 앱 개발자가 CSS를 보지 않고도 주요 화면을 이해할 수 있도록 만든 보조 사양이지만, 실제 네이티브 구현 전에는 반드시 두 파일을 직접 열어 확인해야 합니다.

## 원본 UI 파일 우선순위

UI 재현 기준의 우선순위는 다음과 같습니다.

```text
1순위: 실제 PWA 실행 화면
2순위: src/App.tsx
3순위: src/App.css
4순위: 이 문서의 설명
```

네이티브 구현자는 `src/App.tsx`에서 실제 DOM 구조와 조건부 렌더링을 확인하고, `src/App.css`에서 클래스별 스타일을 확인한 뒤 SwiftUI 화면을 작성합니다. 이 문서에 적힌 수치가 CSS와 다르면 CSS를 우선합니다.

단, iOS 네이티브 앱의 안전영역, 키보드 회피, 권한 요청, 시스템 시트, Dynamic Type, 접근성 설정 때문에 완전히 동일한 배치가 불가능하거나 사용성이 떨어지는 경우에는 iOS 관례를 따릅니다. 이때도 색상, 정보의 우선순위, 버튼의 의미, 화면 흐름은 PWA와 동일하게 유지합니다.

## 전체 톤

앱은 영업 현장에서 반복 사용되는 업무 도구입니다.

따라서:

- 화려한 랜딩 페이지 느낌을 피합니다.
- 운전 중에도 터치하기 쉬운 큰 버튼을 유지합니다.
- 정보는 카드/패널 단위로 분명히 나눕니다.
- 카드 모서리는 대부분 8px 수준입니다.
- 버튼은 기능별로 명확한 색을 사용합니다.
- 과도한 장식, 그라데이션, 큰 일러스트는 사용하지 않습니다.

## 색상 토큰

PWA CSS 기준:

```text
앱 배경: #f5f7fb
기본 텍스트: #162032
보조 텍스트: #667085
placeholder: #98a2b3
흰색 패널: white
옅은 패널: #f8fafc
비활성 버튼: #e8edf5
보조 버튼: #eef2f7
기본 border: #d8dee8
옅은 border: #e5eaf2
primary blue: #1f6feb
success green: #168a53
warning orange text: #b65c17
active dark: #162032
```

SwiftUI에서는 위 색상을 `Color(hex:)` 확장이나 asset catalog로 등록해 사용합니다.

## 폰트와 텍스트

PWA는 시스템 폰트를 사용합니다.

네이티브도 SF Pro 기본 시스템 폰트를 사용하되, 굵기는 PWA와 비슷하게 맞춥니다.

```text
큰 숫자: 24px 수준, bold
카드 제목: 17px 수준, bold
본문/주소: 13~14px 수준
보조 설명: 12~13px 수준
버튼 라벨: 13~15px, heavy
완료 버튼: 19px 수준, heavy
```

letter spacing은 별도로 주지 않습니다.

## 앱 쉘

PWA:

```text
모바일 최대 폭: 480px
태블릿 최대 폭: 920px
PC 최대 폭: 1180px
배경: #f5f7fb
하단 padding: 128px 이상
```

네이티브:

- iPhone에서는 전체 화면을 사용합니다.
- iPad에서는 너무 넓게 퍼지지 않도록 content max width 또는 adaptive grid를 둡니다.
- 배경은 `#f5f7fb`입니다.

## 상단 구조

현재 PWA에는 상단 고정 헤더가 없습니다.

대신 선택된 고객리스트 카드가 화면 상단에 표시됩니다.

### 활성 고객리스트 카드

위치:

- 화면 최상단 컨텐츠 영역
- margin: 12px

스타일:

```text
배경: #162032
텍스트: white
보조 텍스트: rgba(255,255,255,.76)
border-radius: 8px
padding: 12px
레이아웃: 왼쪽 리스트 정보, 오른쪽 변경 버튼
```

오른쪽 `변경` 버튼:

```text
min-height: 42px
background: white
text: #162032
border-radius: 8px
font-weight: 900
```

## 하단 탭바

현재 PWA 하단 탭:

```text
오늘
고객
가져오기
기록
설정
```

스타일:

```text
position: fixed bottom
background: rgba(255,255,255,.96)
border-top: 1px #d8dee8
backdrop blur
grid: 5 columns
padding: 8px 10px 16px
```

탭 버튼:

```text
min-height: 58px
border-radius: 8px
label font-size: 12px
inactive color: #667085
active background: #eaf2ff
active color: #1f6feb
```

네이티브에서는 TabView를 사용해도 되지만, 기본 iOS TabView가 PWA와 너무 다르면 커스텀 하단바를 고려합니다.

## 공통 패널

패널은 흰색 또는 옅은 카드로 구성합니다.

기준:

```text
background: white 또는 #f8fafc
border: 1px solid #d8dee8 또는 #e5eaf2
border-radius: 8px
padding: 보통 12px
margin-bottom: 12px
```

패널 제목:

```text
왼쪽: 제목
오른쪽: meta 숫자/상태
```

예:

```text
고객 목록                         3명
지도 위치 표시                    표시 가능 40/45명
문자 템플릿                       3개
```

## Segmented Control

PWA에는 3분할 또는 4분할 segmented 버튼이 있습니다.

오늘 탭:

```text
스케줄 / 가까운 순 / 지역별 / 지도
```

고객 탭:

```text
미방문 / 완료 / 전체 / 나이별
```

스타일:

```text
gap: 8px
button min-height: 46px
border-radius: 8px
inactive background: #e8edf5
inactive text: #344054
active background: #162032
active text: white
font-weight: 900
```

네이티브 Picker segmented 기본 스타일보다 PWA 버튼형 스타일에 가깝게 직접 구현하는 것이 좋습니다.

## 검색창

검색창은 상단 헤더가 아니라 고객 탭 필터 아래에 있습니다.

위치:

```text
고객 탭:
지도 위치 표시 패널
→ 미방문/완료/전체/나이별 필터
→ 검색창
→ 고객 목록 패널

기록 탭:
검색창
→ 카운트 카드
→ 고객별 히스토리
```

스타일:

```text
min-height: 52px
border: 1px solid #d8dee8
border-radius: 8px
background: white
box-shadow: 0 8px 20px rgba(23,32,50,.05)
padding horizontal: 14px
icon color: #667085
placeholder: 이름·전화번호·주소 검색
```

검색 대상:

- 고객명
- 전화번호 일부
- 주소 일부
- 공백 제거 주소 조각

## 고객 카드

카드형 고객 row:

```text
background: #f8fafc
border: 1px solid #e5eaf2
border-radius: 8px
padding: 12px
gap: 10px
```

표시 내용:

```text
고객명
지역/거리
주소
생년월일/나이 그룹
최근 히스토리
상태 pill
전화/문자/길찾기 버튼
히스토리/메모/수정 버튼
스케줄 추가 버튼
완료 또는 완료취소 버튼
```

완료 고객:

```text
border: #bfe8d3
background: #f1fbf5
opacity: .82
```

상태 pill:

```text
border-radius: 999px
font-size: 12px
font-weight: 900
```

## 카드형/목록형 전환

고객 목록과 기록 목록은 카드형/목록형 전환을 지원합니다.

버튼 위치:

```text
고객 목록 패널 제목 아래 toolbar 왼쪽
카드 / 목록
```

View toggle 스타일:

```text
display: 2-column inline grid
background: #eef2f7
padding: 4px
border-radius: 8px
button min-width: 76px
button min-height: 40px
active background: white
active text: #1f6feb
```

모바일 목록형:

- 카드의 축소판이 아니라 빠른 스크롤용 슬림 텍스트 리스트입니다.
- 행 높이는 낮게 유지하고 첫 줄은 고객명과 연락처를 중심으로 표시합니다.
- 둘째 줄은 지역/주소를 한 줄로 말줄임 처리합니다.
- 상태는 작은 점이나 짧은 색상 신호로만 표시합니다.
- 목록형은 텍스트 위주의 빠른 스크롤 모드이므로 카드형처럼 큰 액션 버튼을 반복 배치하지 않습니다.
- 전화, 문자, 길찾기, 완료, 수정 같은 즉시 조작은 카드형과 상세 화면에서 처리합니다.

PC 목록형:

- 넓은 행 형태입니다.
- 고객 정보와 주요 액션이 한 행에 더 촘촘하게 배치됩니다.

## 액션 버튼

기본 액션:

```text
전화
문자
길찾기
```

보조 액션:

```text
히스토리
메모
수정
```

카드형 버튼:

```text
min-height: 56px
border-radius: 8px
background: #eef2f7
text: #162032
font-weight: 950
```

완료 버튼:

```text
background: #168a53
text: white
font-size: 19px
```

primary 버튼:

```text
background: #1f6feb
text: white
```

## 오늘 탭

화면 순서:

1. 활성 고객리스트 카드
2. segmented control
   - 스케줄
   - 가까운 순
   - 지역별
   - 지도
3. 카운트 카드
   - 남은 고객
   - 터치 고객
   - 완료 고객
4. 선택 모드별 컨텐츠

스케줄/가까운 순:

- 큰 고객 카드 리스트를 표시합니다.
- 완료 고객은 오늘 기본 목록에서 제외됩니다.
- 스케줄 모드는 오늘 스케줄에 추가된 고객을 모두 카드형으로 보여주며, 순차 강제만 하지 않고 랜덤 방문도 가능해야 합니다.

지역별:

- 도로명 기준 그룹 목록을 표시합니다.

지도:

- 오늘 대상 고객 위치를 지도에 표시합니다.

## 고객 탭

화면 순서:

1. 활성 고객리스트 카드
2. 가져온 고객리스트 패널
3. 오늘 스케줄 패널
4. 고객 위치 지도
5. 지도 위치 표시 패널
6. 고객 필터 segmented
   - 미방문
   - 완료
   - 전체
   - 나이별
7. 검색창
8. 고객 목록 패널
   - 카드/목록 toggle
   - 고객 직접 추가 버튼
   - 고객 카드/리스트

중요:

- 사용자는 고객 탭에서 지도와 리스트를 함께 보며 동선을 짭니다.
- 지도는 고객 탭 안에 있어야 합니다.
- 지도에 표시되지 않은 고객명과 원인을 지도 아래에 표시합니다.

## 가져오기 탭

화면 구성:

1. CSV 가져오기 패널
   - CSV 파일 선택
   - 고객사 이름 입력
   - 고객리스트 이름 입력
2. CSV 미리보기/컬럼 매핑 패널
   - 필드별 매핑 select
   - 고객리스트로 저장 버튼

placeholder:

```text
고객사 이름을 입력하세요
예: 7월 강남 방문 리스트
```

주의:

- 고객사 이름/리스트 이름에 기본값을 강제로 채우지 않습니다.
- 회색 placeholder만 보여줍니다.

## 기록 탭

화면 순서:

1. 검색창
2. 카운트 카드
   - 전체 고객
   - 터치 고객
   - 완료 고객
3. 고객별 히스토리 패널
   - 카드/목록 toggle
   - 고객별 최신 히스토리
4. 누적 터치/상담 히스토리 패널
   - 최신순
   - 항목 터치 시 고객 전체보기

완료 고객은 하이라이트되어야 합니다.

## 설정 탭

화면 구성:

1. 앱 설치
   - 홈화면 추가 안내
2. 문자 템플릿
   - 기본 템플릿 목록
   - 수정
   - 삭제
   - 새 템플릿 추가
3. Google Drive 동기화
   - Google 계정으로 연결
   - 연결 계정 이름/이메일
   - 동기화 필요 상태
   - Drive와 동기화
   - Drive 데이터를 이 기기에 가져오기
   - 현재 기기 데이터를 Drive에 저장
   - Google Drive 백업 파일 만들기
4. 백업/복원
   - JSON 백업 내보내기
   - JSON 백업 가져오기

## 문자 시트

문자 버튼을 누르면 하단 시트가 열립니다.

시트:

```text
border-radius: 22px 22px 0 0
background: white
handle bar 표시
제목: 문자 보내기
보조: 고객명 · 연락처
닫기 버튼
```

옵션:

- 사용자 문자보내기
  - 본문 자동 입력 없이 문자앱 열기
- 템플릿 문자
  - 고객 연락처와 템플릿 본문이 입력된 문자 작성창 열기
  - 사용자가 직접 전송 버튼을 누름

고객 카드, 고객 상세, 지도 팝업 어디에서 누르더라도 문자 버튼은 곧바로 문자앱으로 넘어가지 않고 이 선택 시트를 먼저 표시해야 합니다.

iPad/PC 폭에서는 중앙 모달처럼 표시합니다.

## 히스토리/메모/고객 수정 시트

PWA는 하단 sheet 패턴을 반복 사용합니다.

네이티브에서도 가능하면 다음 구조를 유지합니다.

- iPhone: 하단 sheet
- iPad: 중앙 sheet 또는 form sheet
- 제목
- handle 또는 명확한 닫기 버튼
- 입력 필드
- 큰 저장 버튼

## 지도 팝업 카드

지도 고객명 라벨을 누르면 작은 카드가 떠야 합니다.

내용:

```text
순번. 고객명
정규화 주소
스케줄 포함 여부 · 상태
전화 / 문자 / 길찾기
메모 / 이력 / 완료 또는 완료취소
스케줄 추가
```

지도 팝업은 큰 전체 화면 모달이 아니라 지도 위 작은 카드 형태여야 합니다.

## 반응형 기준

PWA breakpoint:

```text
기본: 모바일
760px 이상: 태블릿
1120px 이상: PC
```

모바일:

- 1열 중심
- 하단바 고정
- 큰 터치 버튼

태블릿:

- 2열 grid
- 지도와 주요 목록은 전체 폭
- 하단바는 floating bar처럼 보임

PC:

- 3열 grid
- 카드형은 auto-fill grid
- 목록형은 한 줄 정보 밀도 증가

## 네이티브 UI 구현 지시

SwiftUI에서 단순 `List`만 사용하면 PWA UI와 달라집니다. 정확한 재현을 위해 다음을 권장합니다.

- 공통 `Panel`
- 공통 `ActiveListBanner`
- 공통 `SegmentedButtonGroup`
- 공통 `CustomerCard`
- 공통 `CustomerCompactRow`
- 공통 `ActionGrid`
- 공통 `BottomTabBar` 또는 PWA와 유사한 custom TabView style
- 공통 `BottomSheet`
- 공통 `MetricCard`
- 공통 `ViewModeToggle`

네이티브 기본 컨트롤을 쓰더라도 색상, 간격, radius, 버튼 높이는 이 문서와 `src/App.css` 기준에 맞춥니다.

## 시각 검수 체크리스트

- 하단 탭이 5개인지 확인
- 상단 톱니바퀴가 없는지 확인
- 고객 탭 검색창이 필터 아래에 있는지 확인
- 고객 탭에 지도가 있는지 확인
- 고객 목록에 카드/목록 toggle이 있는지 확인
- 목록형이 모바일에서도 카드형과 확실히 다른지 확인
- 문자 버튼이 하단 시트를 띄우는지 확인
- 고객 카드 버튼 라벨이 세로로 쪼개지거나 겹치지 않는지 확인
- 완료 고객이 초록 계열로 흐리게 표시되는지 확인
- 설정 탭에 Google Drive 동기화와 백업/복원이 있는지 확인
- iPhone, iPad, PC 크기에서 주요 텍스트가 버튼 밖으로 넘치지 않는지 확인
