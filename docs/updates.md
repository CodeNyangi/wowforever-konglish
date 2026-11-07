# Mac 자동 업데이트

시작할 때와 실행 중 6시간마다 공개 저장소 `CodeNyangi/wowforever-konglish`의 최신 정식 GitHub Release를 확인합니다. 번역 내용이나 화면은 전송하지 않습니다. 자동 업데이트 설정은 로컬에 저장합니다.

- 실행 중인 버전보다 높은 `v숫자.숫자.숫자`의 정식 릴리스만 받습니다.
- 현재 CPU에 맞는 `Konglish-버전-mac-arm64.zip` 또는 `mac-x64.zip`만 선택합니다.
- 저장소, 파일 크기, GitHub가 제공하는 SHA-256, 번들 ID, 버전, 코드 서명을 검증합니다. 검증 실패 시 설치하지 않습니다.
- 앱을 종료하거나 와우를 중단하지 않고 받아둡니다. 다음 실행 시 기존 프로세스가 끝난 뒤 앱을 교체하고 다시 엽니다.
- 설치 실패 시 기존 앱을 복원합니다. 이전 앱 한 개를 같은 폴더의 `.Konglish-previous.app`에 보관하고 설정과 번역 언어 파일은 건드리지 않습니다.
- 설치 폴더에 쓰기 권한이 없거나 오프라인이면 현재 앱을 계속 사용할 수 있습니다.

현재 앱은 Apple 공증을 받지 않은 자체 서명 배포본입니다. [Electron 기본 자동 업데이트](https://www.electronjs.org/docs/latest/api/auto-updater)는 macOS 서명 배포가 필요하므로, 검증한 GitHub ZIP을 교체하는 별도 설치기를 사용합니다. SHA-256은 [GitHub Release asset digest](https://docs.github.com/en/rest/releases/assets)와 비교하며, 별도의 개발자 신원 서명을 제공하는 것은 아닙니다.

다음 버전을 배포할 때는 package.json과 package-lock.json의 버전을 올리고, 검사 후 같은 버전의 앱을 빌드합니다. ZIP을 GitHub Release에 올리고 업로드가 끝난 후 정식으로 공개하면 됩니다. 별도 서버나 비밀 키는 필요하지 않습니다.

검사: `npm test`, `npm run test:overlay`. 업데이트 검사는 격리한 작은 Mac 앱으로 다운로드 검증, 설정 유지, 설치, 이전 버전 보관과 잘못된 해시 거절을 확인합니다.
