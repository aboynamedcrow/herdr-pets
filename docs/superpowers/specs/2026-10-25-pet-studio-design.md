# Pet Studio and Broadway Mode

Status: proposal. The user must approve this design before product code changes.

## Purpose

Give the user one place to assign pets, compare their sizes, and control their movement.
Keep the existing Herdr app, fleet polling, and custom pet library.
Use Swift and AppKit, which the app already uses.
This platform choice is the builder's decision.

The user requested these features:

- Add three approved custom pets to the private library.
- Rename the retained younger elf to Dobby.
- Drag any pet into assignments for repositories, agents, and roles.
- Resize custom pets relative to default pets.
- Vary attention animations without changing the current done animation.
- Add Broadway Mode, with pets walking across the screen bottom.
- Show the actual blocked question or approval above a pet as it approaches the pointer.

## Existing behavior

The app has four character modes: By agent type, Random, Village, and Custom.
Custom reads ordered rules from the user's pet library. The first matching rule wins.
Rules can match roles, agent types, and directory prefixes. Each field accepts one value or several values.
Village chooses from built-in and custom pets. It keeps each choice stable.
The current loader uses four custom animation rows. It does not use the walking or gaze rows.

The existing size controls include a global pet size and a custom size boost.
The boost defaults to 130 percent. Each custom pet can take a share of that boost through its metadata.

## Pet Studio window

Add an Open Pet Studio command to the menu popover.
Keep the menu popover for quick visibility, mode, and screen controls.
Use a resizable native window with three tabs: Assignments, Sizes, and Behavior.
Remember the window size and location. Keep the window usable on a small screen.
Use native controls, keyboard focus, VoiceOver labels, and scroll views.

### Assignments

Place a searchable pet palette beside an assignment grid.
The palette contains all built-in pets and every valid custom pet.
Each entry shows its name and thumbnail.

The grid has repository rows and role columns.
The agent-type selector offers All types plus known types, including Claude and Codex.
The role columns include All roles and the roles found in current rules or live panes.
The user can add a role. Repository rows include All repositories and saved directory prefixes.
The user can add a repository with a directory picker or a typed path.
Discovered repositories remain suggestions until the user adds them.

A pet drop creates an explicit assignment for the selected repository, role, and agent type.
A cell menu offers the same operation without dragging.
Clearing a cell removes that explicit assignment and reveals the inherited choice.
Each cell identifies an explicit choice, an inherited choice, or several possible inherited choices.
A details view explains the matching rule and previews current agents affected by the edit.
Do not claim one inherited choice when overlapping legacy rules can produce several choices.

The Agents section lists live panes by machine, label, and repository.
It permits a temporary override for one live agent.
The override lasts for the native agent session. It expires when the session changes or the agent disappears.
This prevents an override from moving to a new occupant of the same pane.
Agent type remains the normal persistent assignment dimension.

### Assignment storage and precedence

Keep legacy rules in their existing order. Do not rewrite them when the user saves grid edits.
Store grid assignments in a separate versioned file in the private pet library.
Store a repository as its directory prefix, not its label.
Match prefixes only at directory boundaries. Preserve the current home expansion behavior.

Resolve Custom choices in this order:

1. An active override for the exact live agent session.
2. A matching explicit grid assignment.
3. The first matching legacy rule.
4. The existing agent-type fallback.

For grid assignments, prefer the longest matching repository prefix.
Within that prefix, prefer an exact role, then an exact agent type.
Use one stored cell for each repository, role, and agent-type combination.
The All values provide defaults. They do not match an empty identity as an exact value.
The details view must show this precedence before Apply.

Edit a draft. Apply saves the draft and refreshes pets immediately.
Cancel discards the draft. A write failure keeps the draft and reports the error.
Resolve existing directory symlinks before atomic writes. Keep a backup of the previous valid file.
Check for external changes before saving. Ask the user to reload a changed file instead of overwriting it.
An invalid file must not clear the last valid assignments.
Other character modes keep their current selection behavior.

### Sizes

Show built-in and custom pets together on one baseline.
Keep the current global pet size control.
Expose the global custom boost from 100 to 200 percent.
Expose each custom pet's share of that boost from 0 to 100 percent.
Show the resulting percentage beside the control.
For example, a 150 percent boost and a 50 percent share produce 125 percent size.
A 100 percent share takes the full boost. A zero share keeps the built-in base size.

Read existing metadata shares as defaults.
Save UI overrides in plugin preferences, without rewriting source artwork or its metadata.
Include Reset controls for each pet and for all size overrides.
Preview changes in the Studio draft. Apply updates the desktop pets.
Keep one shared crop for each custom sheet to prevent frame movement during animation.
Keep every frame within its cell and the screen bounds at the largest size.

### Behavior

Separate character selection from movement mode.
Offer Home Area, which retains the current movement, and Broadway Mode.
Keep the current selected-screen behavior. Do not duplicate one agent across monitors.
Switching movement modes keeps assignments, sizes, and saved home areas.

## Attention animation variety

Attention means the blocked state. The blocked badge remains visible throughout each animation.
For custom pets, choose from available non-travel rows: idle, wave, jump, work, attention, and rest.
Do not use the left-walk or right-walk rows while the pet stands still.
Do not use the done row as a blocked variation.
Finish a loop before choosing another variation. Shuffle the choices and avoid an immediate repeat when alternatives exist.
Give pets independent schedules so the crowd does not change poses together.
Use the existing blocked sequence if another row is absent.
Keep built-in pets' current attention behavior where their artwork has no other poses.

The done state keeps its current sequence, timing, and checkmark.
System Reduce Motion and the existing app control suppress travel and animated variation.
A static blocked pose and its text remain available in that mode.

## Broadway Mode

Use Pet Town's two-dimensional street as movement reference.
Reference: https://github.com/abhishek944/pet-town
Study boundary turns, independent positions, and transparent background interaction.
Keep this app in Swift. Do not add Tauri, Godot, or a second app.
If the builder copies source code, retain its required license notice.

Working pets walk along the bottom of the selected screen's usable area.
They pause, turn at the edges, and resume. Use the appropriate custom walking row for each direction.
Built-in pets retain their existing movement art.
Idle and done pets rest at their assigned bottom positions. Done retains its celebration.
Keep pets inside usable screen bounds and clear of the Dock.
Recompute bounds when the screen arrangement or Dock changes.

Blocked pets leave the bottom lane and approach the pointer on a direct path.
They stop beside it, keep their feet upright, and show a speech bubble above their heads.
Small pointer movements do not cause continuous chasing.
After the block ends, they return to the bottom lane.
This direct approach is the builder's interpretation of the user's request.
Home Area keeps its current screen-edge approach.

Keep bubbles within the screen. Offset overlapping blocked pets and bubbles.
Show one readable bubble near the pointer. Use compact labeled bubbles for the remaining blocked pets.
A click on a compact bubble selects it and reveals its text.
Clicks outside visible interactive regions continue to reach the underlying application.
Do not make the transparent full-screen panel consume all mouse events.

## Actual blocked text

First inspect Herdr's available structured blocked data.
Use a current structured question or approval when the server supplies one.
Otherwise read only the current visible terminal screen for that blocked pane.
Label that fallback as a terminal excerpt. Do not invent or summarize a prompt.
Preserve wording and choices. Wrap long text and provide a scrollable expanded view.
If the source is absent or unreadable, show Waiting for input with Open agent.

Read only blocked panes, with bounded concurrency, output limits, and timeouts.
Keep text in memory. Do not persist it in preferences, logs, or telemetry.
Bind each result to machine, terminal, native session, and request generation.
Drop a result if the agent changes session, changes status, disappears, or becomes unavailable.
Clear text immediately when the agent leaves blocked state.
Do not retain an old question for a new block.

Open agent focuses the exact pane after checking its current identity.
Remote focus uses the saved machine route. A remote error must not focus a local pane.
The bubble shows text and opens the agent. The user answers questions in the agent itself.

## Delivery and checks

Keep personal artwork in private dot. Keep the public plugin changes generic.
Import accepted sheets without regeneration. Preserve their hashes and check their manifests.
The local Codex elf keeps its stable package ID and shows Dobby.
The Herdr library uses a Dobby folder whose metadata ID matches the folder.

Check assignment precedence, legacy fallback, migration, invalid input, and external file conflicts.
Check size calculations, persistence, and missing custom artwork.
Check animation row choices and completion behavior with deterministic inputs.
Check movement at screen edges, pointer approach, mode changes, and Reduce Motion.
Check stale prompt rejection and machine isolation with controlled responses.
Use event-driven test completion. Do not rely on sleeps for ordering.
Run the repository's Swift build and self-test.
Perform native window, drag-and-drop, screen, hit-region, and animation checks.
Use synthetic fixtures in the public repository. Keep private art out of public test output.

Use two independent review lanes on the final source fingerprint before merge.
Update the private plugin pin after the plugin change passes review and checks.
Check the installed result separately from source tests.

## Limits and builder decisions

This work does not create new art, answer approvals, or add a conversational agent.
It does not replace Herdr's fleet routing or change native account settings.
The builder chooses control layout, spacing, animation weights, and movement speeds.
The builder must preserve the behavior and precedence specified above.
