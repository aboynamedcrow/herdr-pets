# Pet Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build the approved assignment editor, size preview, attention variety, and Broadway Mode.

**Architecture:** Keep Swift and AppKit. Use separate models for assignment storage, blocked text, and movement. The native Studio edits a draft before Apply.

**Tech Stack:** Swift 5, AppKit, Core Animation, ImageIO, existing Herdr CLI.

**Spec:** `docs/superpowers/specs/2026-10-25-pet-studio-design.md`.

## Global Constraints

- Keep personal artwork in private dot. Keep the public plugin changes generic.
- Keep legacy rules in their existing order.
- Match prefixes only at directory boundaries.
- Expose the global custom boost from 100 to 200 percent.
- Expose each custom pet's share of that boost from 0 to 100 percent.
- The done state keeps its current sequence, timing, and checkmark.
- Do not persist blocked text in preferences, logs, or telemetry.
- Do not add Tauri, Godot, or a second app.
- Use two independent review lanes on the final source fingerprint before merge.
- Use short sentences. Run STE lint on human-readable files before completion.

## Review Focus

- An external editor changes an assignment file while Studio holds a draft. Apply must report a conflict.
- One pane changes its native agent session during a blocked read. The app must reject the old result.
- A custom pet has no optional animation row. The pet must retain a valid blocked pose.
- A screen changes size with large custom pets. Feet, art, and bubbles must remain on screen.
- A remote pane shares a local terminal ID. Text and focus must keep their machine route.

## Files and responsibilities

| File | Responsibility |
| --- | --- |
| `src/PetAssignments.swift` | Grid model, precedence, draft storage, conflict checks |
| `src/PetStudio.swift` | Native editor, drag/drop, affected-agent preview, sizes |
| `src/StudioTests.swift` | Assignment, persistence, size, animation, and prompt tests |
| `src/BlockedText.swift` | Bounded pane reads and stale-result rejection |
| `src/SpeechBubbles.swift` | Small interactive bubble panels and expanded text |
| `src/RolePets.swift` | Legacy fallback, expanded custom rows, per-pet size share |
| `src/Preferences.swift` | Movement mode and per-pet size preferences |
| `src/Pet.swift` | Attention selection and Broadway movement |
| `src/Scene.swift` | Mode layout, prompt updates, bubbles |
| `src/Herdr.swift` | Pane and native session identity |
| `src/Controls.swift` | Studio entry point |
| `src/main.swift` | Studio initialization and native demo entry points |

### Task 1: Assignment model and storage

**Files:** Create `src/PetAssignments.swift` and `src/StudioTests.swift`. Change `src/RolePets.swift`, `src/Herdr.swift`, and `src/DevTools.swift`.

**Interfaces:**
- Produce `GridAssignment: Codable, Equatable` with repository, role, agentType, and pet strings.
- Produce `AssignmentDocument: Codable, Equatable` with version, repositories, roles, and cells.
- Produce `AssignmentStore.load()`, `save(_:expected:)`, and `winner(for:document:home:)`.
- Expose `RolePets.legacyRules`, `resolve(_:for:)`, and `reload()` to Studio.
- Add optional pane ID and native session fields to `Agent`, plus a session-bound identity.

- [ ] Step 1: Add tests for exact-role and exact-type precedence, longest prefix, prefix boundaries, and legacy fallback.
- [ ] Step 2: Build and run `bin/pets --self-test`. Expect a missing-feature failure.
- [ ] Step 3: Implement the model and first-match legacy fallback. Store overrides in `assignments.json` beside `rules.json`.
- [ ] Step 4: Add persistence checks using a real temporary directory and a directory symlink. Change the file externally before save. Expect a conflict and unchanged external bytes.
- [ ] Step 5: Implement version validation, duplicate-cell rejection, backup, atomic save, and conflict detection. Preserve the last valid document after invalid reads.
- [ ] Step 6: Run the Swift build and self-test. Expect all checks to pass. Commit the model and checks.

### Task 2: Native Studio and size controls

**Files:** Create `src/PetStudio.swift`. Change `src/Preferences.swift`, `src/Controls.swift`, `src/RolePets.swift`, `src/Pet.swift`, and `src/main.swift`.

**Interfaces:**
- Consume Task 1's assignment model and store.
- Produce `PetStudio.show()` and draft Apply/Cancel behavior.
- Produce `Preferences.customSizeShares: [String: Double]` and `movementMode: MovementMode`.
- Produce `CustomPet.frames(sizePercent:share:)`. A nil share uses existing metadata.
- Keep temporary agent overrides in memory, keyed by native session identity.

- [ ] Step 1: Add tests for size persistence, clamping, metadata fallback, and the 150 percent / 50 percent = 125 percent example.
- [ ] Step 2: Run the build and self-test. Expect missing-feature failure.
- [ ] Step 3: Implement size preferences and frame refresh when only a per-pet size changes.
- [ ] Step 4: Build the resizable Studio with Assignments, Sizes, and Behavior tabs. Use AppKit drag/drop plus a cell menu.
- [ ] Step 5: Show repository rows, role columns, and an agent-type filter. Add typed paths and directory selection. Keep discovered repositories as suggestions.
- [ ] Step 6: Show explicit, inherited, and mixed cells. Show the winning rule and affected live agents. Add session-bound live overrides.
- [ ] Step 7: Add comparison previews, reset controls, draft Apply/Cancel, errors, and window restoration.
- [ ] Step 8: Run the build and self-test. Perform a native window smoke check. Commit.

### Task 3: Custom animation variety

**Files:** Change `src/Sprites.swift`, `src/RolePets.swift`, `src/Pet.swift`, and `src/StudioTests.swift`.

**Interfaces:**
- Add optional poses for idle, walking left/right, jump, wave, and rest.
- Keep `Sprites.builtinPoses` fixed at the original four rows.
- Produce `AttentionCycle`, which accepts frame counts and a deterministic seed.
- Consume all available custom rows without requiring optional rows.

- [ ] Step 1: Add tests that reject travel and celebration during blocked variation. Test optional-row fallback and loop-boundary changes without immediate repeats.
- [ ] Step 2: Run the build and self-test. Expect missing-feature failure.
- [ ] Step 3: Expand the loader while preserving one union crop and existing done frames.
- [ ] Step 4: Implement independent attention cycles. Keep a static pose under Reduce Motion.
- [ ] Step 5: Use custom directional walking art without mirroring the guitar or other props.
- [ ] Step 6: Run the build and self-test. Inspect custom frame playback. Commit.

### Task 4: Broadway and blocked bubbles

**Files:** Create `src/BlockedText.swift` and `src/SpeechBubbles.swift`. Change `src/Pet.swift`, `src/Scene.swift`, `src/Overlay.swift`, and `src/StudioTests.swift`.

**Interfaces:**
- Consume `MovementMode.home` and `.broadway` from Task 2.
- Extend `World` with an optional Broadway lane and usable screen bounds.
- Produce `BlockedTextPoller.update(_:)` with injected reader and completion callback.
- Produce bubble updates keyed by machine, terminal, and native session.
- Use separate small interactive panels, leaving the full-screen pet panel click-through.

- [ ] Step 1: Add deterministic movement checks for edge turns, large-art margins, mode changes, and reduced motion.
- [ ] Step 2: Run the build and self-test. Expect missing-feature failure.
- [ ] Step 3: Implement bottom-lane walking, pauses, screen-edge pointer approach, and return after blocked state.
- [ ] Step 4: Add controlled pending-read tests for session replacement, status change, disappearing panes, stale generations, and identical terminal IDs across machines.
- [ ] Step 5: Run the build and self-test. Expect missing-feature failure.
- [ ] Step 6: Implement a bounded CLI reader. Prefer current structured text if available. Otherwise label a visible-screen excerpt. Keep text only in memory.
- [ ] Step 7: Add compact bubbles and a selected readable bubble. Clamp them to the screen. Add a scrollable full-text view and identity-checked Open agent.
- [ ] Step 8: Refresh screen geometry after Dock or screen changes. Preserve the home-area layout and done behavior.
- [ ] Step 9: Run the build and self-test. Perform native movement and hit-region checks. Commit.

### Task 5: Review, private assets, and installed checks

**Files:** Update `README.md` and the private dot plugin pin. Keep the three approved private pet packages in dot.

**Interfaces:** Consume the final plugin commit after review.

- [ ] Step 1: Document Studio, precedence, size controls, and Broadway. Run STE lint.
- [ ] Step 2: Run `mkdir -p bin` and `swiftc -O -swift-version 5 src/*.swift -o bin/pets`. Expect exit zero.
- [ ] Step 3: Run `bin/pets --self-test`. Expect every check to pass.
- [ ] Step 4: Check the native window, drag/drop, keyboard choices, size preview, movement, bubbles, and desktop click-through.
- [ ] Step 5: Run two independent review lanes on the exact plugin head. Resolve blocking findings and repeat review after changes.
- [ ] Step 6: Open the plugin PR. Read its saved title and body. Merge only under standing review and check authority.
- [ ] Step 7: Rebase the private dot branch. Add the immutable plugin pin. Run the dot checks required for those paths.
- [ ] Step 8: Review the exact private dot head in both lanes. Read its saved PR title and body. Merge only after checks pass.
- [ ] Step 9: Apply the approved pin and private library on each reachable Mac. Check the installed source, pet metadata, and app behavior. Report any host that could not be checked.
