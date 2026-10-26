# Avatar Pools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Pet Studio show and edit avatar pools without hiding its controls.

**Architecture:** Keep the assignment precedence and native AppKit window. Extend each cell to a pet pool. Use one stable valid member for each agent.

**Tech Stack:** Swift 5, AppKit, Codable, existing native self-tests and previews.

**Spec:** `docs/superpowers/specs/2026-10-25-avatar-pools.md`

## Global Constraints

- Keep private art in dot. Add no image service or dependency.
- Keep existing single-pet results and assignment document version 1.
- Encode the first member as `pet` for older readers. Add `pets` for a pool.
- Empty UI selection removes the explicit cell. It restores inheritance.
- Keep the existing prefix, role, type, and legacy rule precedence.
- Use the stable machine and terminal identity for pool choices, as Village does.
- Preserve movement, attention settings, backups, and file conflicts.

## Review Focus

- An old single-pet file must load and keep its result.
- Repeated drops must not duplicate members.
- A missing image must not displace a valid pool member with unrelated art.
- An external edit must still block a stale save.
- Many long agent labels must not move Apply off screen.

## Task 1: Store and resolve pools

**Files:** `src/PetAssignments.swift`, `src/RolePets.swift`, `src/StudioTests.swift`.

**Interfaces:** `GridAssignment.pets: [String]`, legacy `pet: String`, and `AssignmentDocument.setPool(_:repository:role:agentType:)`.

- [ ] Add runtime tests for old records, pool persistence, duplicate rejection, stable choices, member removal, and missing art.
- [ ] Build and run `bin/pets --self-test`. Keep the expected failure.
- [ ] Decode old `pet` records. Encode the first member as `pet` and all members as `pets` for pools.
- [ ] Deduplicate UI additions. Reject invalid raw pools. Keep atomic save and backup behavior.
- [ ] Resolve a valid member with the existing rendezvous score. Include every member in gallery possibilities.
- [ ] Run all self-tests and commit the model change.

## Task 2: Edit visual cells

**Files:** Create `src/AvatarAssignments.swift`. Change `src/PetStudio.swift`, `src/DevTools.swift`, `src/main.swift`, and `src/StudioTests.swift`.

**Interfaces:** `AvatarChoice` holds token, name, and image. `AvatarAssignmentTile` shows previews, accepts drops, and returns a pool. Its picker supports one or several choices.

- [ ] Add a native stress preview with many long labels. Inspect a broad cell and check the footer against the screen.
- [ ] Run the old layout and retain its failing result.
- [ ] Add avatar tiles and a visual picker. Drag adds a member. Picker Done updates the cell. Apply saves the changes.
- [ ] Keep inherited previews distinct. Show From rules and a pool count.
- [ ] Label the type scope. Bound toolbar rows and the selected-scope summary.
- [ ] Collapse individual overrides. Keep their list bounded and labels readable.
- [ ] Offer Custom mode activation on Apply. Clamp restored windows to the screen.
- [ ] Run self-tests, real pasteboard checks, and native stress previews. Inspect the images.
- [ ] Update `docs/CHECKS.md`, commit, and run both independent review lanes at the final fingerprint.
- [ ] Open the public PR and private pin PR. Read saved titles and bodies. Wait for CI and review gates.
- [ ] Merge and apply within the standing designation. Check loaded IDs and the actual binary on all three Macs.
