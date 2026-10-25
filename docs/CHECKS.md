# Check herdr-pets

## Scope

Check Pet Studio, Custom assignments, size controls, attention animation, and Broadway Mode.
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

## Native previews

```sh
./bin/pets --demo --studio-preview /tmp/herdr-pets-studio
./bin/pets --broadway-demo --stage-preview /tmp/herdr-pets-stage
```

The first command writes one native image for each Studio tab.
The second writes a native stage image and question bubbles. Its questions are preview fixtures.
Both commands exit after export. They do not save Studio edits or change live agents.
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

1. Drag a palette pet into a grid cell. Check the same choice through its cell menu.
2. Change an assignment and cancel. Reopen Studio. The saved choice must remain.
3. Apply a choice in Custom mode. The affected pet must change without changing its agent identity.
4. Change a custom size share. Compare the preview and desktop result. Check Reset.
5. Move the pointer to each side of the screen. Attention pets must traverse screen edges.
6. Check short and long bubbles. Their size must fit their text and controls within the screen.
7. Click the desktop outside the bubbles. The underlying application must receive the click.
8. Enable Reduce Motion. Check static blocked poses and readable bubbles.
9. Change the selected monitor or Dock placement. Check pet and bubble bounds again.

A demo uses synthetic agent states. It does not read a live agent question.
Quit the owned demo from its own menu. Leave the installed instance running.

## Live blocked text

Use an existing blocked agent after the installed update.
Compare its bubble with the visible terminal question. Do not copy question text into a report.
Select **Open agent**. It must open the matching machine and native session.
When that agent resumes, its bubble must disappear.
A missing or changed session must not open a different agent.
Record native checks separately from synthetic fixtures and source inspection.

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
