# Attention token

The attention daemon owns the pane token `attention`, from source `attention-watch`.
It reports `blocked` with the agent label `attention` before it sets the token.

```sh
herdr pane report-metadata <pane> --source attention-watch --token 'attention=<class>: <first line>'
```

The daemon scrubs the value and limits it to 200 characters.
Herdr 0.9.5 limits stored token values to 80 characters. Clients receive the shorter value.
The token has no provider or session identity. Clients must keep their existing pane and native session checks.

The daemon clears the token with each release. A restart clears tokens from its own source.

```sh
herdr pane report-metadata <pane> --source attention-watch --clear-token attention
```

Herdr returns the string at these JSON paths:

- `pane get`: `result.pane.tokens.attention`.
- `agent list`: `result.agents[].tokens.attention`.
- `api snapshot`: `result.snapshot.panes[].tokens.attention` and `result.snapshot.agents[].tokens.attention`.

Herdr supports `--ttl-ms`. The set and clear commands above do not require a TTL.

`src/BlockedText.swift` uses the token only when the screen read fails or returns no text.
It checks the pane and native session before and after the read. A changed revision rejects the result.
`src/Scene.swift` keeps the native agent type for art and assignments during an attention hold.
It uses `agent_session.agent` or the previous type from the same native session.
