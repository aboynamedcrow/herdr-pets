# Avatar pools in Pet Studio

The user wants visible avatar choices in the repository and role grid.
Each cell can hold one pet or a pool. Drag adds a pet. A visual picker adds or removes several pets.
Each agent gets one valid pool member. The choice stays stable until its rule or pool changes.
Existing single-pet choices keep their result. Empty selection uses inherited rules.

Use native AppKit controls and the system font at 12 pt, with 11 pt secondary text.
Use adaptive semantic colors. The dark references are background #242424, text #efefef, secondary #a0a0a0, border #484848, and selection #0a84ff.
Explicit choices use a blue border. Inherited choices say From rules.
Show avatar groups for pools. A count can cover larger groups. The picker shows every selected member.
Highlight valid drag targets. Keep keyboard and click selection available.

The type selector says Applies to. It sets the rule scope.
Keep the current repository-prefix, role, and type precedence.
Keep individual-agent overrides separate and collapsed by default.
Use a short selected-scope summary with an affected-agent count. Do not dump machine IDs or long task titles.
Keep toolbar rows compact, the grid scrollable, and Apply visible within the screen.
Offer a direct way to use Custom assignments from Studio. Do not switch modes until the user applies that choice.

The layout stays a matrix:

```text
Pet palette | Applies to: [All agent types]
            | Drag onto a tile, or click to choose pets.
            | Repository       All roles       Explorer
            | All repositories [avatar pool]   [avatars]
            | A folder         [avatar]        [avatars]
            | Individual agents [closed]
            | Selected scope and count
Reload                                    Cancel  Apply
```

Keep pet images in private dot. Keep assignment files and preferences private and local.
Preserve atomic writes, backups, and external-edit conflicts.
Check the layout with many long synthetic labels and a selected broad cell.
Native previews do not prove a physical drag or a live provider transition.
