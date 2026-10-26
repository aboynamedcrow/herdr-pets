# herdr-pets

English | [한국어](README.ko.md)

This is the [aboynamedcrow fork](https://github.com/aboynamedcrow/herdr-pets) of [hmu332233/herdr-pets](https://github.com/hmu332233/herdr-pets).

![The 14 herdr-pets characters](assets/readme/characters.png)

![Pets gathered above the Dock, one running toward the pointer](assets/readme/demo.gif)

Each Herdr agent gets a pet on your macOS desktop that runs to your pointer to let you know when the agent is blocked.

## Quick start

Requirements:

- macOS
- [Herdr](https://github.com/ogulcancelik/herdr) 0.9.3 or later
- Xcode Command Line Tools (the app is built with Swift on install)

```sh
herdr plugin install aboynamedcrow/herdr-pets
```

After installation, Herdr starts the app and the pets appear when an agent first changes status.
The app also starts automatically when the Herdr server restarts.

The menu bar shows a pet icon. Click it to open the settings panel.

## How it works

![One pet in the working, blocked, done, and idle poses](assets/readme/poses.png)

| Herdr status | Pet |
| --- | --- |
| `blocked` | Follows screen edges toward your pointer. Shows **!** and varies stationary custom poses |
| `working` | Wanders around |
| `done` | Celebrates and shows **✓** |
| `idle`, `unknown` | Rests |

herdr-pets reads agent status, pane labels, and working folders from Herdr.
The pet overlay passes clicks through. Question bubbles have controls.

## Machines

Pets show agents from Local and every enabled machine in Herdr's saved machine list.
Local refreshes every 2 seconds. Other machines refresh every 6 seconds.
The app reads the machine list at startup and every 60 seconds.
Machine IDs and terminal IDs keep each pet stable.
A pane label or working folder change can select different art without moving the pet.
If a machine poll fails, its pets stay for 60 seconds after the first failure.
After that hold they fall asleep: they rest in place, dimmed, with a gray z badge.
They wake when a poll succeeds. They leave when the machine is disabled or removed, or when the setting is off.
Asleep pets use the slots left after all awake pets, up to the **Max pets** setting.
An agent on an unreachable machine stays on screen while the total count fits that limit.
Only Local failures count toward the app's automatic exit.
Turn **Other machines** off for Local only. This stops new remote calls and removes remote pets.
The app shows awake blocked agents first, then other awake agents, then asleep agents.
**Max pets** sets the limit from 10 to 60, with a default of 20.

## Settings

The settings panel, opened from the menu bar icon, shows the total number of agents and the number of blocked agents at the top.

<img src="assets/readme/settings-en.png" alt="herdr-pets settings panel" width="340">

| Setting | Description |
| --- | --- |
| **Characters: By agent type** | Claude and Codex use their own characters. Other types keep a fixed character. Rules do not apply |
| **Characters: Random** | Each pane keeps one of the 14 built-in characters |
| **Characters: Village** | Each pane keeps a built-in or valid custom pet. Rules do not apply |
| **Characters: Custom** | Use Studio assignments, then the first matching legacy rule. This is the default |
| **Show pets** | Show or hide the pets |
| **Other machines** | Show agents from enabled saved machines. On by default |
| **Max pets** | Show 10 to 60 pets. Default 20, in steps of 5 |
| **Custom pet size** | Scale custom art from 100% to 200%. Default 130%, in steps of 10 |
| **Pet size** | Adjust pet size from 16–72 pt while **!** and **✓** stay the same size |
| **Reduce motion** | Pets show status through poses without moving, and also follow the macOS Reduce Motion setting |
| **Movement: Mode** | **Home area** or **Broadway**. A click applies the mode at once |
| **Movement: Alerts** | **Bubbles** show blocked text. **Icon only** shows the **!** alone |
| **Movement: Cluster** | **Off**, **Machine**, or **Project**. Pets gather in one group for each machine or project |
| **Home area → Set…** | Move and resize the translucent window, then close it to save its position and size |
| **Monitor** | With two or more monitors, choose which one shows the pets. The home area moves to the same spot on that monitor |
| **Language** | Defaults to the macOS language. Switch to 한국어 or English |
| **Quit** | Quit the app |

Settings are saved in the plugin config folder, which you can locate with this command:

```sh
herdr plugin config-dir dev.minung.herdr-pets
```

## Pet Studio

Click **Open Pet Studio…** in the menu panel.
The window has three tabs. Resize it to suit your screen.

- **Assignments:** Drag a pet from the palette into a repository and role cell. Select an agent type above the grid.
- **Sizes:** Compare custom pets with a default pet. Change the base size, custom boost, and each custom pet's share.
- **Behavior:** Choose the movement mode, the cluster mode, question bubbles, and Reduce Motion. Set keyboard shortcuts. These settings apply at once, with no Apply.

Cell menus offer the same choices as dragging. Choose **Use inherited choice** to clear an explicit cell.
The grid marks inherited choices with an arrow. **Multiple choices** means the current rules can select different pets.
Click a cell to see the matching source and affected live agents.
Add a repository with a typed path or folder picker. Live repositories remain suggestions until you add them.
The live-agent rows permit overrides that expire with the native agent session.

**Apply** saves the draft. **Cancel** discards changes since the last Apply.
The app keeps legacy `rules.json` unchanged. It stores grid choices in `assignments.json` beside that file.
A backup keeps the previous valid choices. An external edit causes a save conflict. Use **Reload** before trying again.

Custom selection uses this order:

1. An override for the exact live agent session.
2. A grid assignment, preferring the longest repository prefix, then an exact role, then an exact agent type.
3. The first matching legacy rule.
4. The agent-type fallback.

Size overrides remain in plugin preferences. Reset a pet to use its metadata share again.
For example, a 150% custom boost and a 50% share give that pet 125% size.
The preview uses actual frames from the app, including their shared crop.

### Broadway Mode

Working pets walk along the line of the home area. They pause and turn at the ends of the screen.
A home area at the bottom gives a walk across the bottom. A home area in the middle gives a walk at its height.
A home area snapped to the left or right edge gives a vertical walk along that edge.

### Edges and clusters

Snap the home area flush to a screen edge. The pets then stand with their feet on that edge.
On the top edge, they stand upside down. On a side edge, they stand sideways.
A home area a few points away from an edge keeps the pets upright.
The area editor is darker when the area is flush with an edge.
In a corner, the edge along the longer side of the area wins.

**Cluster** splits the home area into one group for each machine or project.
Each group gets space in proportion to its pet count. Local agents come first.
The project is the repository folder from the agent's working directory. A worktree path uses its repository name.
In Broadway, each group walks only its own part of the line.

### Keyboard shortcuts

Set shortcuts in **Pet Studio → Behavior**. Click a field, then press the keys. Press Escape to cancel.
A shortcut needs a modifier key, or a function key such as F13.
A Karabiner hyper key arrives as ⌃⌥⇧⌘. Shortcuts need no Accessibility permission.

| Action | Result |
| --- | --- |
| Show or hide pets | The same as **Show pets** |
| Bubbles or icon only | Changes the alert style |
| Home area or Broadway | Changes the movement mode |
| Show or hide the home area window | Opens or closes the area editor, so you can drag it |
| Move to the next monitor | Moves the home area to the next monitor at the same place, with the same flush edges |

If macOS or another app already uses a combination, Studio shows an error and keeps the field empty.
In both modes, attention pets follow the original screen-edge route toward the pointer.
They do not cross the screen interior to chase it.
The done animation and checkmark remain the same.

Broadway shows blocked text in a bubble above each pet.
One bubble shows its text. Click a compact bubble to select another pet.
Each bubble fits its text and controls. Long text wraps and scrolls only when it cannot fit on screen.
Herdr 0.9.5 supplies a visible terminal excerpt. The bubble labels that source.
The app checks the machine, terminal, native session, and screen revision before it accepts a read.
**Open agent** checks the session again before focusing its pane.
If the text is unavailable, the bubble shows **Waiting for input**.
Answers remain in the agent. The app keeps question text in memory.

Movement reference: [Pet Town](https://github.com/abhishek944/pet-town).
This app keeps its Swift and AppKit implementation.

## Role pets

Keep custom art and `rules.json` in `$XDG_CONFIG_HOME/herdr/pets`, or `~/.config/herdr/pets` when XDG is unset.
`HERDR_PETS_DIR` overrides that folder.
Rules form an ordered JSON list. The first matching rule wins:

```json
[
  {"role": ["researcher", "explorer"], "cwd": "~/projects/", "pet": "sample"},
  {"role": "reviewer", "agent": "codex", "pet": "generic"}
]
```

Each optional match field accepts a string or a list of strings.
`role` matches the first word in a pane label without case. One leading marker emoji is allowed.
`agent` matches the agent type exactly.
`cwd` matches a path prefix on a folder boundary. A leading `~` expands to the local home.
All fields in a rule must match.

| `pet` value | Choice |
| --- | --- |
| `"agent"` | The **By agent type** choice |
| `"generic"` | One of the 12 generic characters, stable for each pet key |
| A built-in name, such as `"cat"` | That built-in character |
| A custom ID, such as `"sample"` | Art from the subfolder with that ID. Custom art takes priority over a built-in name |

Each custom folder needs `pet.json` and a PNG or WebP sheet:

```json
{"id":"sample","displayName":"Sample","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp","customSizeShare":0.5}
```

`customSizeShare` is optional. It sets the share of the **Custom pet size** boost that applies to this pet.
It defaults to 1. The loader clamps numbers to 0...1.
A value that is not a number uses 1. The pet still loads, and the file logs one warning.
The effective percent is `100 + (customPetSize - 100) * customSizeShare`.
For example, `sample` with a share of 0.5 uses 115% at a 130% setting and 150% at 200%.
A share of 0 keeps the pet at 100%. Built-in pets do not use this key.

Use a Codex v2 sheet: 1536 x 2288 pixels, with 8 columns and 11 rows of 192 x 208 cells.
Leave unused cells transparent. The loader counts frames from their alpha channel within each row's frame limit.
Walking uses rows 1 and 2. Stationary attention uses available rows 0, 3, 5, 6, 7, and 8.
Celebrate keeps row 4. Resting keeps row 0. Working keeps row 7.
All frames share one crop box. **Custom pet size** scales custom frames. **Pet size** scales all pets.
The loader decodes custom art once for 200% at the largest pet size on Retina screens.

**Characters** has four modes: **By agent type**, **Random**, **Village**, and **Custom**.
**Custom** applies the rules above. An unmatched pane uses **By agent type**.
**Random** keeps the same built-in pet for each pane across polls and restarts.
**Village** includes all valid custom folders, even those without a rule.
It scores each candidate from the pet key and candidate ID.
Adding or removing a candidate changes only panes whose winning candidate changes.
A failed unrelated custom pet does not change another pick.
With no valid custom art, **Village** still scores the built-in candidates. Its picks can differ from **Random**.
With no grid assignments or rules, **Custom** equals **By agent type**.
The gallery shows built-in pets first, then custom pets, seven per row.
It dims pets the mode cannot produce. Custom tooltips show `displayName`.
**Custom pet size** defaults to 130%. It ranges from 100% to 200% in steps of 10.
Old settings migrate to **Custom** when Role pets was on or absent.
When Role pets was off, All 14 migrates to **Random**. The other choice migrates to **By agent type**.
**Max pets** sets the pet limit from 10 to 60. It defaults to 20, with steps of 5.
Missing art uses the agent-type fallback for that choice. Invalid legacy rules do not remove valid Studio assignments.
Each bad art or legacy file logs an error only once.
The app reads art at startup. Only **Custom** mode reads legacy rules.
Art and legacy rules check file changes at most every 60 seconds. Studio Apply reloads them immediately.
Studio assignments reload during polling and settings refresh.

## Turn off or uninstall

If you quit the app from the menu bar, the plugin starts it again the next time an agent changes status. Use the `stop` action to turn off the pets and `start` to bring them back while keeping the plugin enabled.

```sh
herdr plugin action invoke stop --plugin dev.minung.herdr-pets
herdr plugin action invoke start --plugin dev.minung.herdr-pets
```

To turn off the plugin as well, use `disable`, then quit the app from the menu bar.

```sh
herdr plugin disable dev.minung.herdr-pets    # to remove: herdr plugin uninstall dev.minung.herdr-pets
```

After you update or uninstall the plugin, quit the running app from the menu bar as well.
The app quits by itself about 30 seconds after the Herdr server stops.

## Troubleshooting

If no pets appear, start by checking the plugin status and recent run logs.

```sh
herdr plugin list --plugin dev.minung.herdr-pets
herdr plugin log list --plugin dev.minung.herdr-pets --limit 20
```

- After installation, an agent must change status before the pets appear.
- If a run shows exit code 1, `bin/pets` was not built.
  Install Xcode Command Line Tools with `xcode-select --install`, then reinstall the plugin.
- Only one instance of the app runs at a time. With multiple Local Herdr sessions, it reads the session that started it first.

## Development

```sh
mkdir -p bin
swiftc -O -swift-version 5 src/*.swift -o bin/pets
./bin/pets --self-test
```

Herdr does not build linked plugins, so build your local changes first, then link the project with this command:

```sh
herdr plugin link .
```

You can also run the app directly.

| Command | Description |
| --- | --- |
| `./bin/pets` | Show pets for running Herdr agents |
| `./bin/pets --demo` | Show all 14 characters without Herdr, changing their status every 12 seconds |
| `./bin/pets --self-test` | Check images, characters, movement, and machine polling with fake fetchers and a clock |
| `./bin/pets --export-frames <directory>` | Export frame images to check that animations do not jitter |

When run directly, the app finds `herdr` through `PATH` or `HERDR_BIN_PATH` and saves settings in `pets-preferences.json` in the project folder.

### Character images

Character images are transparent PNGs, with poses or frames arranged side by side in equal-width cells.

| File | Contents |
| --- | --- |
| `assets/sheets/<kind>.png` | Four poses: working, blocked, celebrate, resting |
| `assets/frames/<kind>-<pose>.png` | Optional animation for one pose: 4 frames for working and celebrate, 2 for blocked and resting |
| `assets/sheets/manifest.json` | How the images were made, with prompts |
| `assets/menubar-icon.png` | Menu bar icon |

If no animation file is available, the pet uses the pose from the sheet. Align each frame by the feet and the horizontal center of the body to prevent jitter during animation.

Bug reports and pull requests are welcome.

The Claude and Codex characters are fan art, and this project is not affiliated with Anthropic or OpenAI.

See [the verification recipe](docs/CHECKS.md) for native checks and preview commands.
