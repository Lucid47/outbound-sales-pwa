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

## 네이티브 iOS TestFlight 배포

현재 네이티브 앱 배포 설정은 다음과 같습니다.

```text
앱 이름: 소희야 가자
Bundle ID: com.lucid47.outboundsales
Apple Developer Team: 35PZ4DJ283
버전: 1.0
최근 업로드: 빌드 4 (2026-07-18)
업로드 소스: testflight/1.0-build-4, 커밋 d44a03674b60ec95f7a50f3cf916b6d5dd721fea
업로드 도구: Xcode 26.6, iOS 26.5 SDK
TestFlight 상태: 내부 기능 검증·외부 베타 테스트 그룹 배포 완료
```

빌드별 기능, Git 태그, 데이터 호환성과 원복 절차는 `docs/release-history.md`를 기준으로 관리합니다.

TestFlight 업로드는 iOS/iPadOS 바이너리를 대상으로 합니다. App Store Connect 앱 레코드에서 macOS 플랫폼을 함께 선택했더라도 macOS 타깃 또는 Mac Catalyst 빌드를 별도로 만들기 전까지 macOS 앱은 포함되지 않습니다.

### 빌드 전 확인

- `MARKETING_VERSION`은 사용자에게 표시할 앱 버전입니다.
- `CURRENT_PROJECT_VERSION`은 업로드마다 증가해야 하는 빌드 번호입니다.
- 실제 업로드 소스에는 `testflight/<버전>-build-<번호>` 형식의 Git 태그를 생성합니다.
- `Info.plist`의 `CFBundleVersion`은 `$(CURRENT_PROJECT_VERSION)`을 사용합니다.
- 앱 아이콘 PNG에는 알파 채널이 없어야 합니다.
- 앱은 HTTPS, Apple Keychain, CryptoKit의 PKCE SHA-256 등 Apple 운영체제에 포함된 면제 암호화만 사용합니다.
- `Info.plist`의 `ITSAppUsesNonExemptEncryption`을 `false`로 유지하면 빌드마다 수출 규정 질문이 반복되지 않습니다.

### 아카이브와 업로드

App Store Connect가 현재 허용하는 Xcode 버전을 먼저 확인해야 합니다. 기존 TestFlight 빌드는 계속 실행되더라도, 지원 기간이 지난 beta Xcode로 만든 새 빌드는 업로드 단계에서 거절될 수 있습니다. 2026-07-18 기준 제출용 기본 도구는 Xcode 26.6이며 Xcode 27 beta를 사용하려면 beta 3 이상이어야 합니다.

안정판 Xcode가 `/Applications/Xcode.app`에 설치된 환경의 예시입니다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project native/OutboundSalesiOS/OutboundSalesiOS.xcodeproj \
  -scheme OutboundSalesiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/SoheeyaGaja-TestFlight.xcarchive \
  -allowProvisioningUpdates \
  archive
```

ExportOptions plist에는 `method=app-store-connect`, `destination=upload`, `signingStyle=automatic`, `teamID=35PZ4DJ283`을 사용합니다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -exportArchive \
  -archivePath /tmp/SoheeyaGaja-TestFlight.xcarchive \
  -exportPath /tmp/SoheeyaGaja-TestFlight-export \
  -exportOptionsPlist /tmp/SoheeyaGaja-ExportOptions.plist \
  -allowProvisioningUpdates
```

업로드 성공 후 App Store Connect가 빌드를 처리하는 동안 TestFlight에 즉시 나타나지 않을 수 있습니다. 처리 완료 후 내부 테스트 그룹을 만들고 빌드와 테스터를 추가합니다. 외부 테스터 배포는 별도의 Beta App Review가 필요합니다.

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
