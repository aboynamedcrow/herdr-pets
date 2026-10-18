# herdr-pets

English | [한국어](README.ko.md)

![The 14 herdr-pets characters](assets/readme/characters.png)

![Pets gathered above the Dock, one running toward the pointer](assets/readme/demo.gif)

herdr-pets is a Herdr plugin that puts a pet on your macOS desktop for each Herdr agent.  
The pets stay together above the Dock. When an agent is blocked, its pet runs to your pointer and waves.  
When the agent is unblocked, the pet goes back home.

## Quick start

Requirements:

- macOS
- [Herdr](https://github.com/ogulcancelik/herdr) 0.9.3 or later
- Xcode Command Line Tools (the app is built with Swift on install)

```sh
herdr plugin install hmu332233/herdr-pets
```

After install, Herdr starts the app and the pets appear the first time an agent changes status.
The app also starts automatically when the Herdr server restarts.

A pet icon appears in the menu bar. The number next to it is the count of blocked agents.
Click the icon to open the settings panel.

## How it works

![One pet in the working, blocked, done, and idle poses](assets/readme/poses.png)

| Herdr status | Pet |
| --- | --- |
| `blocked` | Runs to your pointer, shows **!**, and waves |
| `working` | Wanders around |
| `done` | Celebrates and shows **✓** |
| `idle`, `unknown` | Rests |

Pets never block clicks or take focus, and herdr-pets reads only agent status from Herdr.

## Settings

Click the menu bar icon to open the settings panel. The top shows the number of agents and
blocked agents.

<img src="assets/readme/settings-en.png" alt="herdr-pets settings panel" width="340">

| Setting | Description |
| --- | --- |
| **By agent type** | Claude and Codex get their own characters; other agents get a fixed character per agent type |
| **All 14** | Each agent gets one of all 14 characters |
| **Show pets** | Show or hide the pets |
| **Pet size** | 16–72 pt. The **!** and **✓** keep their size |
| **Reduce motion** | Pets show status with poses only, without moving. The macOS Reduce Motion setting also applies |
| **Home area → Set…** | Move and resize the translucent window, then close it to save |
| **Language** | 한국어 or English. Follows the macOS language at first |
| **Quit** | Quit the app |

Settings are saved in the plugin config folder. To find it:

```sh
herdr plugin config-dir dev.minung.herdr-pets
```

## Turn off or uninstall

If you quit the app from the menu bar, the plugin starts it again the next time an agent
changes status. To turn it off, disable the plugin and then quit the app from the menu bar.

```sh
herdr plugin disable dev.minung.herdr-pets    # to remove: herdr plugin uninstall dev.minung.herdr-pets
```

After you update or uninstall the plugin, quit the running app from the menu bar as well.
The app quits by itself about 30 seconds after the Herdr server stops.

## Troubleshooting

If no pets appear, check the plugin and its recent runs.

```sh
herdr plugin list --plugin dev.minung.herdr-pets
herdr plugin log list --plugin dev.minung.herdr-pets --limit 20
```

- Right after install, pets appear once an agent changes status.
- If a run shows exit code 1, `bin/pets` was not built.
  Install Xcode Command Line Tools with `xcode-select --install`, then reinstall the plugin.
- Only one app runs at a time. With several Herdr sessions, only the session that started it first gets pets.

## Development

```sh
mkdir -p bin
swiftc -O -swift-version 5 src/*.swift -o bin/pets
./bin/pets --self-test
```

To connect a local checkout to Herdr, build it first and then link it. Herdr does not build
linked plugins.

```sh
herdr plugin link .
```

You can also run the app directly.

| Command | Description |
| --- | --- |
| `./bin/pets` | Show pets for running Herdr agents |
| `./bin/pets --demo` | Show all 14 characters without Herdr. Their status changes every 12 seconds |
| `./bin/pets --self-test` | Check images, character selection, and movement without a window |
| `./bin/pets --export-frames <directory>` | Export frame images to check that animations do not jitter |

When run directly, the app finds `herdr` through `PATH` or `HERDR_BIN_PATH`, and saves
settings in `pets-preferences.json` in the project folder.

### Character images

All images are transparent PNGs, with poses or frames side by side in equal-width cells.

| File | Contents |
| --- | --- |
| `assets/sheets/<kind>.png` | Four poses: working, blocked, celebrate, resting |
| `assets/frames/<kind>-<pose>.png` | Optional animation for one pose: 4 frames for working and celebrate, 2 for blocked and resting |
| `assets/sheets/manifest.json` | How the images were made, with prompts |
| `assets/menubar-icon.png` | Menu bar icon |

Without an animation file, the pose from the sheet is used. Frames are aligned at the feet and
the horizontal center of the body, so they do not jitter.

Bug reports and pull requests are welcome.

The Claude and Codex characters are fan art. This project is not affiliated with Anthropic or OpenAI.
