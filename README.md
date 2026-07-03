# 아웃바운드 영업 도우미 PWA

개인 사용을 목표로 한 무료 운영 방식의 PWA 프로젝트입니다.

PWA는 Progressive Web App의 약자로, 웹으로 만들지만 아이폰 Safari에서 홈 화면에 추가해 앱처럼 사용할 수 있는 방식입니다.

## 추천 개발 순서

1. 프로젝트 기본 세팅
2. IndexedDB 데이터 모델 구현
3. CSV import와 헤더 자동 인식 구현
4. 고객리스트별 저장/조회 구현
5. 오늘 스케줄 구현
6. 현재 위치와 가까운 순 정렬 구현
7. 지도 핀 표시 구현
8. 전화/문자/길찾기 연결 구현
9. 방문/문자 로그 구현
10. 백업/복원 구현
11. Cloudflare Pages 무료 배포
12. 아이폰 Safari에서 홈 화면에 추가

## 설치된 주요 라이브러리

- `dexie`: IndexedDB 로컬 데이터베이스
- `papaparse`: CSV 파싱
- `leaflet`: 지도 표시
- `react-leaflet`: React용 Leaflet 연결
- `vite-plugin-pwa`: PWA manifest/service worker 생성
- `lucide-react`: 아이콘

## 로컬 실행

이 작업공간에서는 번들 Node/pnpm 경로를 사용합니다.

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" pnpm dev --host 0.0.0.0
```

아이폰에서 같은 Wi-Fi로 접속하려면 Mac의 로컬 IP를 확인한 뒤 다음 주소로 접속합니다.

```text
http://맥IP주소:5173
```

단, 위치 기능과 PWA 설치 테스트는 HTTPS 배포 환경에서 확인하는 것이 가장 안정적입니다.

## 빌드

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" pnpm build
```

빌드 결과는 `dist/`에 생성됩니다.

## 무료 배포 추천

1순위는 Cloudflare Pages입니다.

권장 흐름:

```text
GitHub 저장소 생성
→ 이 프로젝트 push
→ Cloudflare Pages에서 저장소 연결
→ Build command: pnpm build
→ Output directory: dist
→ 배포 URL 접속
→ iPhone Safari에서 홈 화면에 추가
```

## 데이터 저장 정책

초기 버전은 서버 없이 동작하도록 설계합니다.

```text
앱 파일: Cloudflare Pages 또는 GitHub Pages에서 제공
고객 데이터: 아이폰 브라우저의 IndexedDB에 저장
백업: JSON/CSV 내보내기
복원: 백업 파일 가져오기
```

이 방식은 무료 운영과 개인정보 보호에 유리하지만, Safari 데이터 삭제나 기기 변경에 대비해 백업/복원 기능이 필수입니다.

## PWA 제약

문자 기능은 네이티브 앱보다 제한이 있습니다.

가능:

```text
전화번호로 문자 앱 열기
템플릿 본문을 클립보드에 복사
사용자가 문자 앱에서 붙여넣고 전송
```

불가능:

```text
사용자 개입 없는 SMS 자동 전송
웹앱에서 iOS 문자 본문을 안정적으로 자동 삽입
```
