# Google Drive 동기화

## 현재 방식

앱은 사용자 데이터를 중앙 서버가 아니라 사용자의 Google Drive에 저장합니다.

```text
로컬 저장: IndexedDB
기본 동기화: Google Drive appDataFolder
사용자 백업: 일반 Google Drive JSON 파일
```

네이티브 앱에서는 로컬 저장 원본이 앱 샌드박스입니다. 고객리스트/고객/히스토리/스케줄/템플릿은 JSON 메타데이터로 저장하고, 고객별 사진 기록은 앱 내부 사진 폴더에 저장합니다. Google Drive 연결 전에는 이 둘을 하나의 전체 백업 JSON으로 묶어 내보내고 가져옵니다.

## 장점

- 별도 서버 비용이 없습니다.
- 사용자의 고객 데이터가 운영자 서버에 저장되지 않습니다.
- 사용자는 본인 Google 계정으로 본인 데이터를 보관합니다.
- iPhone, iPad, PC 간 같은 Google 계정으로 복원할 수 있습니다.

## Google OAuth 설정

현재 Google Auth Platform 설정:

```text
User type: External
Publishing status: In production
Authorized JavaScript origin: https://lucid47.github.io
```

GitHub Variables:

```text
VITE_GOOGLE_CLIENT_ID
```

앱에서 사용하는 권한:

```text
openid
email
profile
https://www.googleapis.com/auth/drive.appdata
https://www.googleapis.com/auth/drive.file
```

## 사용자 흐름

기존 기기:

```text
설정
→ Google 계정으로 연결
→ 권한 허용
→ Drive와 동기화
```

새 기기:

```text
설정
→ Google 계정으로 연결
→ Drive 데이터를 이 기기에 가져오기
→ 로컬 데이터를 Drive 데이터로 교체 복원
→ 이후 Drive와 동기화 사용
```

일상 사용:

```text
고객 수정, 전화, 문자, 메모, 완료 처리 등 로컬 변경
→ 설정 화면에 동기화 필요 표시
→ Drive와 동기화
→ 마지막 동기화 시간 갱신
```

## 병합 정책

- 고객리스트, 고객, 스케줄, 로그, 템플릿은 ID 기준으로 병합합니다.
- 네이티브 사진 기록은 고객 ID와 사진 ID 기준으로 병합하고, 실제 사진 파일은 백업 payload 또는 Drive appDataFolder 파일로 함께 보관합니다.
- 같은 ID가 양쪽에 있으면 더 최근 수정 시각을 우선합니다.
- 로그성 데이터는 ID 기준으로 합쳐 데이터 유실을 줄입니다.
- `Drive 데이터를 이 기기에 가져오기`는 병합이 아니라 로컬 데이터 교체 복원입니다.

## 현재 제한

- 삭제 동기화는 아직 완전하지 않습니다.
- 삭제 동기화를 안정화하려면 `deletedAt` 필드와 tombstone 정책이 필요합니다.
- 앱이 완전히 닫힌 상태에서 백그라운드 자동 동기화는 보장하지 않습니다.
- Google access token은 저장하지 않고 버튼을 누를 때마다 새로 요청합니다.
- 실제 Google 로그인/권한 동의 화면은 Google 정책 변경에 따라 문구가 바뀔 수 있습니다.

## 운영 참고

- OAuth 앱은 Production 상태이므로 테스트 사용자 이메일을 직접 추가하지 않아도 사용할 수 있습니다.
- 사용자가 처음 연결할 때 Google 권한 동의 화면이 표시됩니다.
- 만약 `unverified app` 화면이 보이면 OAuth 브랜딩/권한 검토가 추가로 필요할 수 있습니다.
