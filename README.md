# Codex Claude Usage Bar

Codex와 Claude Code의 구독형 사용량을 Windows 시스템 트레이에서 확인하는 작은 도구입니다. 별도 대시보드 창 없이 트레이 아이콘을 우클릭하면 사용량 카드가 열립니다.

이 프로젝트는 설치형 EXE가 아니라 VBS가 PowerShell 스크립트를 콘솔 창 없이 실행하는 포터블 스크립트형 앱입니다. 실행 파일을 설치하지 않아도 되지만, VBS와 `dev.ps1`은 같은 폴더에 있어야 합니다.

## 표시 내용

- Codex 및 Claude의 5시간(5h)·주간(7d) 사용률
- 남은 비율과 재설정 시각
- 주간 한도는 재설정 **날짜와 시각** 표시
- 사용률 게이지: 초록(0–59%) / 주황(60–79%) / 빨강(80% 이상)
- 원격 서비스 호출은 5분 간격으로 제한하고, 마지막 정상 값을 유지

## 가장 쉬운 실행 방법

`Codex Claude Usage Bar.vbs`를 더블클릭하세요. PowerShell이나 콘솔 창이 열리지 않고 시스템 트레이에서 실행됩니다.

이미 실행 중일 때 다시 더블클릭해도 새 인스턴스는 만들어지지 않습니다.

처음 실행하면 사용할 제공자를 선택하는 등록 화면이 나타납니다.

- Codex만 사용: **Codex**만 선택
- Claude만 사용: **Claude**만 선택
- 둘 다 사용: 둘 다 선택

등록 후에는 작업표시줄 오른쪽의 숨겨진 아이콘 영역에서 **Codex Claude Usage Bar** 아이콘을 우클릭해 사용량을 봅니다.

## 다른 사람이 사용하기 전 준비

이 도구는 각 사용자의 PC에 이미 로그인된 Codex 또는 Claude Code 계정만 읽습니다. 다음 중 사용하는 서비스만 준비하면 됩니다.

### Codex 사용량을 표시하려면

1. Codex CLI를 설치합니다.
2. PowerShell에서 ChatGPT 계정으로 로그인합니다.

```powershell
codex login
```

브라우저를 열 수 없으면 다음을 사용합니다.

```powershell
codex login --device-auth
```

### Claude 사용량을 표시하려면

1. Claude Code를 설치합니다.
2. 터미널에서 `claude`를 실행하고 Claude.ai 구독 계정으로 로그인합니다.

첫 등록 화면에는 각 제공자의 상태가 **Ready** 또는 **Not signed in**으로 표시됩니다. 아직 준비되지 않은 제공자를 선택한 경우에도 트레이 카드에 필요한 로그인 방법을 표시합니다.

## 설정 변경 및 종료

트레이 아이콘을 우클릭한 뒤 다음 메뉴를 사용합니다.

- `Configure providers...`: Codex / Claude 표시 여부 변경
- `Exit`: 프로그램 완전 종료

또는 `Configure Codex Claude Usage Bar.vbs`를 더블클릭해 등록 화면을 다시 열 수 있습니다.

## Windows 시작 시 자동 실행

먼저 이 폴더를 앞으로 옮기지 않을 위치에 둡니다. 시작프로그램의 바로가기는 현재 폴더 경로를 사용하므로, 나중에 폴더를 옮기면 바로가기를 다시 만들어야 합니다.

1. `Codex Claude Usage Bar.vbs`를 우클릭하고 **바로 가기 만들기**를 선택합니다.
2. `Win + R`을 누르고 `shell:startup`을 입력한 뒤 Enter를 누릅니다.
3. 만들어진 바로가기를 열린 시작프로그램 폴더로 옮깁니다.
4. 다음 Windows 로그인부터 대시보드가 자동으로 실행됩니다.

VBS 파일 자체만 시작프로그램 폴더에 복사하면 안 됩니다. VBS는 자신과 같은 폴더의 `dev.ps1`을 실행하므로, 원본 VBS를 가리키는 **바로가기**를 등록해야 합니다.

자동 실행을 해제하려면 `Win + R`에서 `shell:startup`을 다시 열고 해당 바로가기를 삭제하면 됩니다.

## PowerShell로 실행하기

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\dev.ps1
```

설정 화면을 강제로 다시 열려면 다음을 실행합니다.

```powershell
.\dev.ps1 -Setup
```

## 필요한 로그인 상태

- **Codex**: ChatGPT 계정 로그인 방식의 Codex CLI가 필요합니다. API 키 전용 사용량은 ChatGPT 구독의 5시간·7일 한도와 다릅니다.
- **Claude**: Claude.ai 구독 계정으로 Claude Code에 로그인되어 있어야 합니다. API 키 전용 사용량은 별도입니다.

각 서비스에 로그인하지 않았거나 선택하지 않은 제공자는 사용량을 조회하지 않습니다.

## 다른 사람에게 공유하기

이 폴더 전체를 ZIP으로 압축해 전달하세요. 받는 사람은 압축을 풀고 `Codex Claude Usage Bar.vbs`를 더블클릭하면 됩니다.

각 사용자는 자신의 Windows 계정으로 Codex와 Claude Code에 로그인해야 합니다. 이 도구는 실행한 사용자의 `%USERPROFILE%\.codex` 및 `%USERPROFILE%\.claude` 경로를 자동으로 사용합니다.

**인증 파일, API 키, 토큰은 절대 함께 복사하거나 공유하지 마세요.**

Windows가 다운로드한 파일을 차단하는 경우 파일을 우클릭하고 **속성 → 차단 해제**를 선택한 뒤 다시 실행하세요.

## 포함 파일

- `Codex Claude Usage Bar.vbs` — 더블클릭 실행
- `Configure Codex Claude Usage Bar.vbs` — 제공자 등록/변경
- `dev.ps1` — 트레이 앱 본체
- `README.md` — 설치, 실행 및 공유 안내

## 참고

사용량 조회 경로는 Codex와 Claude Code의 로컬 로그인 정보를 사용해 각 계정의 서버에서 읽습니다. 토큰을 화면이나 별도 서버로 전송·저장하지 않습니다. 제공사가 개인 사용량 조회 응답을 변경하면 카드에 오류가 표시될 수 있습니다.

이 프로젝트는 비공식 커뮤니티 도구이며 OpenAI 또는 Anthropic과 제휴하거나 보증받지 않았습니다. Codex, OpenAI, Claude 및 Anthropic은 각 소유자의 상표입니다.

## 라이선스

MIT License로 배포됩니다. 자세한 내용은 `LICENSE`를 확인하세요.
