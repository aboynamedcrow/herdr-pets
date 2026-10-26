# Check herdr-pets

## Scope

Check Pet Studio, Custom assignments, size controls, attention animation, Broadway Mode, edge snaps, clusters, and shortcuts.
Use an existing Herdr installation and the current source checkout.
Do not restart the Herdr server for these checks.

## Build and self-test

```sh
mkdir -p bin
swiftc -O -swift-version 5 src/*.swift -o bin/pets
./bin/pets --self-test
```

The build must exit zero. Every self-test must pass.
Keep the build log and test log. Preserve each exit code when redirecting output.
The self-tests use synthetic art and controlled fetchers. They do not prove live provider behavior.
They cover assignments, file conflicts, size calculations, animation choices, screen bounds, stale text, and machine separation.

## Installed custom library

```sh
./bin/pets --check-library
./bin/pets --check-library sample
```

The first command lists custom pets that the app can load.
The second requires a custom pet with ID `sample`. Use the IDs required by the installation.
A missing ID must exit one. File hashes alone do not prove that the loader finds each pet.
Run this check on each Mac after a plugin or library update.
A library root can be a Stow link. The scan must include folders without rules.

## Native previews

```sh
./bin/pets --demo --studio-preview /tmp/herdr-pets-studio
./bin/pets --demo --studio-preview /tmp/herdr-pets-pools --stress-layout --check-picker
./bin/pets --broadway-demo --stage-preview /tmp/herdr-pets-stage
./bin/pets --demo --menu-preview /tmp/herdr-pets-menu
```

The first command writes one native image for each Studio tab.
The third writes a native stage image and question bubbles. Its questions are preview fixtures.
The fourth writes `menu.png`, the menu panel with its Movement section.
The demo agents use three machines and two projects, so a stage preview with **Cluster** set shows groups.
Save a home area flush with the top edge in the preview preferences. The stage preview must then show upside-down pets.
These commands exit after export. They do not save Studio edits or change live agents.
The pool check uses 60 long agent labels and a 900 by 600 pt window.
It checks that Apply stays on screen. It selects two avatars through native button actions.
It checks that the picker stays open and keeps the draft after Done. It also exports the picker.
Use separate preview preferences with no saved broad-cell assignment for this check.
Add `--custom-demo` to inspect installed custom art.
Set `HERDR_PETS_DIR` to use a separate custom library.
Set `HERDR_PLUGIN_CONFIG_DIR` to use separate preview preferences.
Keep custom images local when the library is private.

Inspect each image for missing controls, cropped art, text clipping, excess bubble space, and unreadable choices.
A preview is an AppKit render with simulated movement time. It does not prove a physical mouse drag or live prompt detection.

## Native interaction

```sh
./bin/pets --broadway-demo --studio
```

Use the menu panel to open Studio if you close the window.

1. Drag two palette pets into a grid tile. Both avatars must appear. Click the tile to add or remove members in the picker.
2. Change an assignment and cancel. Reopen Studio. The saved choice must remain.
3. Apply a choice in Custom mode. The affected pet must change without changing its agent identity.
4. Change a custom size share. Compare the preview and desktop result. Check Reset.
5. Check question bubbles on and off in both movement modes. Then move the pointer to each side of the screen. Attention pets must traverse screen edges.
6. Check short and long bubbles. Their size must fit their text and controls within the screen.
7. Click the desktop outside the bubbles. The underlying application must receive the click.
8. Enable Reduce Motion. Check static blocked poses and readable bubbles.
9. Change the selected monitor or Dock placement. Check pet and bubble bounds again.
10. Change Mode, Alerts, and Cluster in the menu panel. Each change must apply with no other click.
11. Drag the home area flush to the top edge. The pets must turn upside down. Move it 3 pt away. They must stand upright again.
12. Snap the home area to the left edge in Broadway. The pets must walk vertically along that edge.
13. Set Cluster to Machine and to Project. Check one group for each value, in both movement modes.
14. In the installed app, record a shortcut for each action in Studio. Press each one, also from another app. Record an enabled macOS shortcut, such as ⌃Space. Studio must show an error and keep the previous value. A demo process does not register shortcuts.
15. With two monitors, press the next-monitor shortcut. The home area must keep its place and flush edges.

A demo uses synthetic agent states. It does not read a live agent question.
Quit the owned demo from its own menu. Leave the installed instance running.

## Live blocked text

Use an existing blocked agent after the installed update.
Compare its bubble with the visible terminal question. Do not copy question text into a report.
Select **Open agent**. It must open the matching machine and native session.
When that agent resumes, its bubble must disappear.
A missing or changed session must not open a different agent.
Record native checks separately from synthetic fixtures and source inspection.

Collapsed bubbles show a short question preview. Expand one to see the latest question and choices.
The reader prefers the final visible question. For other formats, it uses a bounded recent paragraph or option group.
It does not read the full provider conversation. Native question extraction remains a heuristic over visible terminal text.
On 2026-10-25, native probes checked Codex and Claude prompt samples, wrapped borders, and an option group without a question mark.
The probes also rendered three bubbles. The two collapsed bubbles showed the question.

## Repair limit

Classify a failure as a product defect, documentation drift, or a verification gap.
Repair only the approved feature. Retry at most three times per failure.
After that limit, keep the evidence and report the unresolved result.
Do not weaken a check to obtain a passing result.

## Evidence and cleanup

Record the source commit, macOS version, build exit code, and checks completed.
List each native interaction that the available tools could not drive.
Keep screenshots and logs in a task folder outside the repository.
Close owned preview windows and processes after each check.
Keep user settings, real agent panes, and private art unchanged except for approved edits.
