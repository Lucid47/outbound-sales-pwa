# 배포와 운영

## 저장소

```text
https://github.com/Lucid47/outbound-sales.git
```

## 운영 주소

```text
https://lucid47.github.io/outbound-sales/
```

## 배포 방식

현재 배포는 GitHub Pages와 GitHub Actions를 사용합니다.

```text
main 브랜치 push
→ GitHub Actions 실행
→ pnpm install
→ pnpm build
→ dist 업로드
→ GitHub Pages 반영
```

## 로컬 개발

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" pnpm dev --host 0.0.0.0
```

## 검사

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" pnpm lint
```

## 프로덕션 빌드

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" DEPLOY_TARGET=github-pages pnpm build
```

## GitHub Pages 배포 확인

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" gh run list --repo Lucid47/outbound-sales --limit 3
```

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" gh run watch <run-id> --repo Lucid47/outbound-sales --exit-status
```

## 배포 실패 대응

GitHub Pages 배포 단계에서 간헐적으로 다음 유형의 실패가 발생한 적이 있습니다.

```text
Deployment failed, try again later.
```

이 경우 앱 빌드 실패가 아니라 Pages 배포 서비스의 일시 오류였고, 실패한 작업만 재실행하면 정상 배포되었습니다.

```bash
PATH="/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/daehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin:$PATH" gh run rerun <run-id> --repo Lucid47/outbound-sales --failed
```

## 공개 페이지 반영 확인

```bash
curl -L -s https://lucid47.github.io/outbound-sales/ | rg "assets/index|manifest"
```

## iPhone 확인 주의사항

- 홈화면에 추가한 PWA는 서비스워커 캐시 때문에 새 배포가 즉시 보이지 않을 수 있습니다.
- 앱을 완전히 종료 후 재실행하거나 Safari에서 새로고침하면 반영됩니다.
- 위치 기능, 홈화면 PWA, 외부 앱 연결은 HTTPS 배포 환경에서 확인하는 것이 안정적입니다.
