# herdr-pets

[English](README.md) | 한국어

![herdr-pets의 캐릭터 14종](assets/readme/characters.png)

![Dock 위에 모여 있던 펫이 커서 쪽으로 달려가는 모습](assets/readme/demo.gif)

Herdr 에이전트마다 macOS 화면에 펫이 나타나고, 에이전트가 block되면 커서 옆으로 달려와 알려 줍니다.

## 빠른 시작

필요한 것:

- macOS
- [Herdr](https://github.com/ogulcancelik/herdr) 0.9.3 이상
- Xcode Command Line Tools (설치할 때 Swift로 앱을 빌드합니다)

```sh
herdr plugin install hmu332233/herdr-pets
```

설치 후 에이전트 상태가 처음 바뀌면 Herdr가 앱을 실행하고 펫이 나타납니다.
Herdr 서버를 다시 시작할 때도 앱이 자동으로 실행됩니다.

메뉴 막대에는 펫 아이콘이 표시되며, 아이콘을 누르면 설정 패널이 열립니다.

## 동작 방식

![working, blocked, done, idle 상태의 펫 포즈](assets/readme/poses.png)

| Herdr 상태 | 펫 |
| --- | --- |
| `blocked` | 커서 옆으로 달려와 **!** 를 띄우고 손을 흔듭니다 |
| `working` | 돌아다닙니다 |
| `done` | 축하하고 **✓** 를 띄웁니다 |
| `idle`, `unknown` | 쉽니다 |

herdr-pets는 Herdr의 에이전트 상태, 패널 이름, 작업 폴더를 읽습니다.
펫은 클릭이나 포커스를 가로채지 않습니다.

## 설정

메뉴 막대 아이콘으로 여는 설정 패널에서는 맨 위에 전체 에이전트 수와 block된 에이전트 수가 표시됩니다.

<img src="assets/readme/settings.png" alt="herdr-pets 설정 패널" width="340">

| 설정 | 설명 |
| --- | --- |
| **에이전트 종류대로** | Claude와 Codex는 전용 캐릭터로, 나머지 에이전트는 종류별로 정해진 캐릭터로 보여 줍니다 |
| **14종 골고루** | 에이전트마다 14종 가운데 하나를 골라 보여 줍니다 |
| **펫 표시** | 펫을 표시하거나 숨깁니다 |
| **역할별 펫** | 펫 폴더의 규칙을 적용합니다. 기본값은 켜짐입니다 |
| **최대 펫 수** | 10마리부터 60마리까지 표시합니다. 기본값은 20마리이며 5마리씩 조절합니다 |
| **펫 크기** | 펫 크기를 16–72 pt 사이에서 조절하며, **!** 와 **✓** 크기는 그대로 유지됩니다 |
| **동작 줄이기** | 펫이 포즈로만 상태를 알리도록 움직임을 줄이며, macOS의 동작 줄이기 설정도 따릅니다 |
| **모이는 곳 → 정하기…** | 반투명 창을 원하는 위치로 옮기고 크기를 조절한 뒤 닫으면 위치와 크기가 저장됩니다 |
| **모니터** | 모니터가 2대 이상일 때 펫을 보여 줄 모니터를 고르며, 모이는 곳도 그 모니터의 같은 자리로 옮겨집니다 |
| **언어** | 기본값은 macOS 언어이며, 한국어나 English로 바꿀 수 있습니다 |
| **종료** | 앱을 종료합니다 |

설정은 플러그인 설정 폴더에 저장되며, 아래 명령으로 폴더 위치를 확인할 수 있습니다.

```sh
herdr plugin config-dir dev.minung.herdr-pets
```

## 역할별 펫

사용자 이미지와 `rules.json`은 `$XDG_CONFIG_HOME/herdr/pets`에 둡니다. XDG가 없으면 `~/.config/herdr/pets`를 사용합니다.
`HERDR_PETS_DIR`로 폴더를 바꿀 수 있습니다.
규칙은 순서가 있는 JSON 목록입니다. 처음 일치하는 규칙을 사용합니다:

```json
[
  {"role": ["researcher", "explorer"], "cwd": "~/projects/", "pet": "sample"},
  {"role": "reviewer", "agent": "codex", "pet": "generic"}
]
```

각 선택 조건에는 문자열 하나나 문자열 목록을 사용할 수 있습니다.
`role`은 패널 이름의 첫 단어를 대소문자 구분 없이 비교합니다. 맨 앞에 표시용 이모지 하나를 둘 수 있습니다.
`agent`는 에이전트 종류와 정확히 일치해야 합니다.
`cwd`는 폴더 경계에서 경로 접두사를 비교합니다. 맨 앞의 `~`는 로컬 홈 폴더로 바뀝니다.
규칙의 모든 조건이 일치해야 합니다.

| `pet` 값 | 선택 |
| --- | --- |
| `"agent"` | 현재 **에이전트 종류대로** 또는 **14종 골고루** 설정 |
| `"generic"` | 일반 캐릭터 12종 중 하나. 각 펫 키마다 고정됩니다 |
| `"cat"` 같은 내장 이름 | 해당 내장 캐릭터 |
| `"sample"` 같은 사용자 ID | 해당 ID의 하위 폴더에 있는 이미지. 내장 이름보다 사용자 이미지가 우선합니다 |

각 사용자 폴더에는 `pet.json`과 PNG 또는 WebP 시트가 필요합니다:

```json
{"id":"sample","displayName":"Sample","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp"}
```

Codex v2 시트를 사용합니다. 크기는 1536 x 2288픽셀이며, 192 x 208픽셀 셀을 8열과 11행으로 배치합니다.
쓰지 않는 셀은 투명하게 둡니다. 로더는 각 행의 프레임 한도 안에서 알파 채널로 프레임 수를 셉니다.
작업은 7행, 대기는 6행, 축하는 4행, 휴식은 0행을 사용합니다.
모든 프레임은 하나의 자르기 영역을 공유하며 **펫 크기**에 맞춰 크기가 바뀝니다.

**역할별 펫**은 기본으로 켜져 있습니다. 끄면 규칙 없이 현재 캐릭터 설정을 사용합니다.
**최대 펫 수**는 펫 한도를 10마리부터 60마리까지 정합니다. 기본값은 20마리이며 5마리씩 조절합니다.
규칙이나 이미지가 없거나 잘못되면 현재 설정을 사용합니다. 각 파일의 오류는 한 번만 기록합니다.
앱은 시작할 때 규칙과 이미지를 읽습니다. 변경된 파일은 최대 60초마다 확인합니다.

## 끄기와 제거

메뉴 막대에서 앱을 종료해도 다음에 에이전트 상태가 바뀌면 플러그인이 앱을 다시 실행합니다.
플러그인을 켜 둔 채 펫만 끄려면 `stop`, 다시 켜려면 `start` 액션을 사용합니다.

```sh
herdr plugin action invoke stop --plugin dev.minung.herdr-pets
herdr plugin action invoke start --plugin dev.minung.herdr-pets
```

플러그인까지 끄려면 `disable`로 비활성화한 뒤 메뉴 막대에서 앱을 종료합니다.

```sh
herdr plugin disable dev.minung.herdr-pets    # 제거하려면: herdr plugin uninstall dev.minung.herdr-pets
```

플러그인을 업데이트하거나 제거한 뒤에도 실행 중인 앱은 메뉴 막대에서 직접 종료해야 합니다.
Herdr 서버가 꺼지면 앱도 30초쯤 뒤에 스스로 종료됩니다.

## 문제 해결

펫이 나타나지 않으면 먼저 플러그인 상태와 최근 실행 기록을 확인합니다.

```sh
herdr plugin list --plugin dev.minung.herdr-pets
herdr plugin log list --plugin dev.minung.herdr-pets --limit 20
```

- 설치 직후에는 에이전트 상태가 한 번 바뀌어야 펫이 나타납니다.
- 실행 기록에 종료 코드 1이 남아 있다면 `bin/pets`가 빌드되지 않은 상태입니다.
  `xcode-select --install`로 Xcode Command Line Tools를 설치한 뒤 플러그인을 다시 설치하면 됩니다.
- 앱은 한 번에 하나만 실행되므로 Herdr 세션을 여러 개 쓰더라도 먼저 앱을 실행한 세션의 펫만 보입니다.

## 개발

```sh
mkdir -p bin
swiftc -O -swift-version 5 src/*.swift -o bin/pets
./bin/pets --self-test
```

Herdr는 link한 플러그인을 빌드해 주지 않으므로, 로컬에서 고친 코드를 연결하려면 먼저 빌드한 뒤 아래 명령으로 link합니다.

```sh
herdr plugin link .
```

앱을 직접 실행할 수도 있습니다.

| 명령 | 설명 |
| --- | --- |
| `./bin/pets` | 실행 중인 Herdr 에이전트의 펫을 보여 줍니다 |
| `./bin/pets --demo` | Herdr 없이 14종을 모두 보여 주며, 12초마다 상태가 바뀝니다 |
| `./bin/pets --self-test` | 창을 띄우지 않고 이미지, 캐릭터 배정, 움직임을 검사합니다 |
| `./bin/pets --export-frames <directory>` | 애니메이션이 떨리지 않는지 확인할 수 있게 프레임 이미지를 내보냅니다 |

앱을 직접 실행할 때는 `PATH`나 `HERDR_BIN_PATH`에서 `herdr`를 찾고, 설정을 프로젝트 폴더의 `pets-preferences.json`에 저장합니다.

### 캐릭터 이미지

캐릭터 이미지는 모두 투명 PNG로, 같은 폭의 칸에 포즈나 프레임을 가로로 나란히 배치합니다.

| 파일 | 내용 |
| --- | --- |
| `assets/sheets/<kind>.png` | 포즈 4개: working, blocked, celebrate, resting |
| `assets/frames/<kind>-<pose>.png` | 한 포즈의 애니메이션(선택). working과 celebrate는 4장, blocked와 resting은 2장 |
| `assets/sheets/manifest.json` | 이미지를 만든 방법과 프롬프트 |
| `assets/menubar-icon.png` | 메뉴 막대 아이콘 |

애니메이션 파일이 없으면 시트에 있는 포즈를 그대로 사용합니다. 각 프레임은 움직일 때 떨리지 않도록 발 위치와 몸의 가로 중심을 기준으로 맞춥니다.

버그 제보와 풀 리퀘스트를 환영합니다.

Claude와 Codex 캐릭터는 팬 아트이며, 이 프로젝트는 Anthropic, OpenAI와 관련이 없습니다.
