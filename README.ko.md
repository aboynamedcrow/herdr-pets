# herdr-pets

[English](README.md) | 한국어

![herdr-pets의 캐릭터 14종](assets/readme/characters.png)

![Dock 위에 모여 있던 펫이 커서 쪽으로 달려가는 모습](assets/readme/demo.gif)

herdr-pets는 Herdr 에이전트마다 macOS 화면에 펫을 띄워 주는 플러그인입니다.  
펫들은 평소 Dock 위에 모여 있다가, 에이전트가 block되면 커서 옆으로 달려와 손을 흔듭니다.  
block이 풀리면 원래 자리로 돌아갑니다.

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

메뉴 막대에 펫 아이콘이 생기고, 아이콘 옆 숫자는 block된 에이전트 수입니다.
아이콘을 누르면 설정 패널이 열립니다.

## 동작 방식

![working, blocked, done, idle 상태의 펫 포즈](assets/readme/poses.png)

| Herdr 상태 | 펫 |
| --- | --- |
| `blocked` | 커서 옆으로 달려와 **!** 를 띄우고 손을 흔듭니다 |
| `working` | 돌아다닙니다 |
| `done` | 축하하고 **✓** 를 띄웁니다 |
| `idle`, `unknown` | 쉽니다 |

펫은 클릭이나 포커스를 가로채지 않으며, herdr-pets는 Herdr의 에이전트 상태만 읽습니다.

## 설정

메뉴 막대 아이콘을 누르면 설정 패널이 열립니다. 맨 위에서 전체 에이전트 수와 block된
에이전트 수를 볼 수 있습니다.

<img src="assets/readme/settings.png" alt="herdr-pets 설정 패널" width="340">

| 설정 | 설명 |
| --- | --- |
| **에이전트 종류대로** | Claude와 Codex는 전용 캐릭터로, 나머지 에이전트는 종류별로 정해진 캐릭터로 보여 줍니다 |
| **14종 골고루** | 에이전트마다 14종 가운데 하나를 골라 보여 줍니다 |
| **펫 표시** | 펫을 보이거나 숨깁니다 |
| **펫 크기** | 16–72 pt 사이에서 조절합니다. **!** 와 **✓** 크기는 바뀌지 않습니다 |
| **동작 줄이기** | 펫이 움직이지 않고 포즈로만 상태를 알려 줍니다. macOS의 동작 줄이기 설정도 따릅니다 |
| **모이는 곳 → 정하기…** | 반투명 창을 원하는 위치로 옮기고 크기를 조절한 뒤, 창을 닫아 저장하세요 |
| **언어** | 한국어나 English를 고릅니다. 처음에는 macOS 언어를 따릅니다 |
| **종료** | 앱을 종료합니다 |

설정은 플러그인 설정 폴더에 저장됩니다. 위치는 아래 명령으로 확인할 수 있습니다.

```sh
herdr plugin config-dir dev.minung.herdr-pets
```

## 끄기와 제거

메뉴 막대에서 앱을 종료해도, 다음에 에이전트 상태가 바뀌면 플러그인이 앱을 다시 실행합니다.
완전히 끄려면 플러그인을 비활성화한 뒤 메뉴 막대에서 앱을 종료하세요.

```sh
herdr plugin disable dev.minung.herdr-pets    # 제거하려면: herdr plugin uninstall dev.minung.herdr-pets
```

플러그인을 업데이트하거나 제거한 뒤에도 실행 중인 앱은 메뉴 막대에서 직접 종료하세요.
Herdr 서버가 꺼지면 앱도 30초쯤 뒤에 스스로 종료됩니다.

## 문제 해결

펫이 나타나지 않으면 플러그인 상태와 최근 실행 기록을 확인하세요.

```sh
herdr plugin list --plugin dev.minung.herdr-pets
herdr plugin log list --plugin dev.minung.herdr-pets --limit 20
```

- 설치 직후에는 에이전트 상태가 한 번 바뀌어야 펫이 나타납니다.
- 실행 기록에 종료 코드 1이 남아 있다면 `bin/pets`가 빌드되지 않은 것입니다.
  `xcode-select --install`로 Xcode Command Line Tools를 설치한 뒤 플러그인을 다시 설치하세요.
- 앱은 한 번에 하나만 실행됩니다. Herdr 세션을 여러 개 쓰면 먼저 앱을 실행한 세션의 펫만 보입니다.

## 개발

```sh
mkdir -p bin
swiftc -O -swift-version 5 src/*.swift -o bin/pets
./bin/pets --self-test
```

로컬에서 고친 코드를 Herdr에 연결하려면 먼저 빌드한 뒤 link하세요. link한 플러그인은 Herdr가
빌드해 주지 않습니다.

```sh
herdr plugin link .
```

앱을 직접 실행할 수도 있습니다.

| 명령 | 설명 |
| --- | --- |
| `./bin/pets` | 실행 중인 Herdr 에이전트의 펫을 보여 줍니다 |
| `./bin/pets --demo` | Herdr 없이 14종을 모두 보여 줍니다. 12초마다 상태가 바뀝니다 |
| `./bin/pets --self-test` | 창을 띄우지 않고 이미지, 캐릭터 배정, 움직임을 검사합니다 |
| `./bin/pets --export-frames <directory>` | 애니메이션이 떨리지 않는지 확인할 수 있게 프레임 이미지를 내보냅니다 |

직접 실행하면 `herdr`는 `PATH`나 `HERDR_BIN_PATH`에서 찾고, 설정은 프로젝트 폴더의
`pets-preferences.json`에 저장합니다.

### 캐릭터 이미지

이미지는 모두 투명 PNG이며, 포즈나 프레임을 같은 폭의 칸에 가로로 나란히 그립니다.

| 파일 | 내용 |
| --- | --- |
| `assets/sheets/<kind>.png` | 포즈 4개: working, blocked, celebrate, resting |
| `assets/frames/<kind>-<pose>.png` | 한 포즈의 애니메이션(선택). working과 celebrate는 4장, blocked와 resting은 2장 |
| `assets/sheets/manifest.json` | 이미지를 만든 방법과 프롬프트 |
| `assets/menubar-icon.png` | 메뉴 막대 아이콘 |

애니메이션 파일이 없으면 시트에 있는 포즈를 그대로 씁니다. 프레임은 발 위치와 몸의 가로 중심을
기준으로 맞춰서 움직일 때 떨리지 않습니다.

버그 제보와 풀 리퀘스트를 환영합니다.

Claude와 Codex 캐릭터는 팬 아트입니다. 이 프로젝트는 Anthropic, OpenAI와 관련이 없습니다.
