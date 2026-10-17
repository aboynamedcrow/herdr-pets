# Agent Pets

English | [한국어](README.ko.md)

Agent Pets shows the status of Herdr agents on macOS. Each agent has one pet.

Pets stay in a set area of the screen. This area is the **home area**. When an agent needs input, its pet moves along the screen edge toward the pointer.

## Requirements

- macOS with an active desktop session.
- Xcode Command Line Tools.
- Herdr for live agent status. Demo mode does not require Herdr.

Keep the executable in `bin`. Keep the `assets` folder in the project folder.

## Install as a Herdr plugin

```sh
herdr plugin install <owner>/herdr-agent-pets   # builds bin/pets
```

For a local checkout, build `bin/pets` first (see below), then run `herdr plugin link .`. Herdr does not build linked plugins.

The plugin starts the app when the Herdr server starts and on each agent status change. Only one app runs at a time. The app quits 30 seconds after the Herdr server stops. If you quit the app from the menu bar, the next status change starts it again. To turn it off, run `herdr plugin disable dev.minung.agent-pets`, then quit the app from the menu bar. Quit the app the same way after you update or uninstall the plugin.

## Build and start

1. Open a terminal in the project folder.
2. Build the app:

   ```sh
   mkdir -p bin
   swiftc -O -swift-version 5 src/*.swift -o bin/pets
   ```

3. Start the app:

   ```sh
   ./bin/pets
   ```

The app reads agent status with `herdr agent list` every two seconds. It finds `herdr` through `PATH`. To use a different executable, set `HERDR_BIN_PATH` to its path.

To stop the app, open the menu bar panel and select **종료** (Quit). You can also press **Ctrl-C** in the terminal.

## Command options

| Command | Function |
|---|---|
| `./bin/pets --demo` | Show all 14 characters without Herdr. Change their status every 12 seconds. |
| `./bin/pets --self-test` | Check image assets, character selection, and movement without an app window. |
| `./bin/pets --export-frames <directory>` | Export images for frame alignment checks. Replace `<directory>` with an output path. |

## Pet status

The default home area is 260 × 80 pt. It is near the lower-right corner of the screen, above the Dock.

| Agent status | Pet behavior |
|---|---|
| `working` | The pet moves inside the home area. It makes small movements during short stops. |
| `idle`, `unknown` | The pet rests without movement. |
| `done` | The pet shows a celebration, then rests. The green ✓ stays visible while the status is `done`. |
| `blocked` | The pet jumps, moves to the nearest screen edge, and follows the edge toward the pointer. It shows an orange ! and waves. |

A blocked pet follows the pointer when the pointer moves far enough. When the status changes, the pet returns to the home area.

The movement path stays below the menu bar and above the Dock. The pet turns to keep its feet toward the screen edge. It turns gradually at corners.

The app shows a maximum of 20 pets. If there are more agents, blocked agents have priority. The number next to the menu bar icon shows the number of blocked agents.

The app uses 15 frames per second for normal movement and 30 for fast movement. It stops drawing when all pets are at rest.

## Settings

Select the menu bar icon to open the settings panel. The panel shows the agent count and the blocked agent count. The status text is orange when an agent is blocked.

The controls use Korean labels.

| Control | Function |
|---|---|
| **에이전트 종류대로** (By agent type) | Use dedicated characters for Claude and Codex. Select one of the other 12 characters for each other agent type. |
| **14종 골고루** (All 14 characters) | Assign a character to each agent from all 14 characters. |
| **펫 표시** (Show pets) | Show or hide the pets. |
| **펫 크기** (Pet size) | Set the pet size from 16 to 72 pt. The ! and ✓ marks keep the same size. |
| **동작 줄이기** (Reduce motion) | Use fixed poses instead of movement. The app also uses the macOS Reduce Motion setting. |
| **모이는 곳 → 정하기…** (Set home area) | Open the home area editor. |

The character gallery dims characters that are not available with the current settings and agent types.

The app saves settings and the home area in `pets-preferences.json` in the project folder. When Herdr starts the app as a plugin, the file is in the plugin config folder (`herdr plugin config-dir dev.minung.agent-pets`).

## Character images

Use transparent PNG files. Put each pose or frame in a cell of equal width. Arrange the cells in one horizontal row.

| File | Contents |
|---|---|
| `assets/sheets/<kind>.png` | Four poses, in this order: working, blocked, celebrate, resting. |
| `assets/frames/<kind>-<pose>.png` | Optional animation frames for one pose. |
| `assets/menubar-icon.png` | The menu bar icon. |
| `assets/sheets/manifest.json` | Image generation methods and prompts. |

Replace `<kind>` with the character name. Replace `<pose>` with a pose name from this table:

| Pose name | Frame count |
|---|---|
| `working` | 4 |
| `blocked` | 2 |
| `celebrate` | 4 |
| `resting` | 2 |

If an animation file is absent, the app uses the pose from the main image sheet.

The app aligns frames at the feet and at the horizontal center of the opaque pixels. This reduces unwanted movement between frames.

The Claude and Codex characters are fan art. This project is not affiliated with Anthropic or OpenAI.

## Source files

| File | Function |
|---|---|
| `src/main.swift` | Read command options, create the app window and scene, and schedule status checks. |
| `src/Herdr.swift` | Read Herdr agent status and create demo agents. |
| `src/Sprites.swift` | Select characters and prepare image frames. |
| `src/Pet.swift` | Control pet movement and the path along the screen edge. |
| `src/Scene.swift` | Add and remove pets, update frames, and pause drawing. |
| `src/Overlay.swift` | Create the transparent window and manage the home area. |
| `src/Controls.swift` | Create the menu bar icon and settings panel. |
| `src/Preferences.swift` | Read and save settings. |
| `src/DevTools.swift` | Run the self-test and export frames. |
