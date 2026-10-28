# Attention token

The attention daemon owns the pane token `attention`, from source `attention-watch`.
The token alone marks a pane that needs ingwon. The pane can stay `idle`.
The daemon does not report `blocked` or change the agent label.
Pets show attention when the state is `blocked` or the token is not empty.
An attention token takes priority over a done celebration.

```sh
herdr pane report-metadata <pane> --source attention-watch --token 'attention=<class>: <first line>'
```

The daemon scrubs the value and limits it to 200 characters.
Herdr 0.9.5 limits stored token values to 80 characters. Clients receive the shorter value.
The token has no provider or session identity. Clients must keep their existing pane and native session checks.

The daemon clears the token when the pane no longer needs ingwon.
If the state is not `blocked`, this removes the badge and bubble.
A restart clears tokens from its own source.

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

The reader keeps the last good text for one native session while attention continues.
A screen revision change or failed read does not clear that text.
A screen excerpt replaces it. The reader records that revision as read.
An attention fallback appears only when no screen text exists. It never records a revision as read or stops retries.
A new session or the end of attention clears stored text.
The reader reads when screen text is missing or the last successful revision differs.
Without a revision, successful reads cannot record a revision. They repeat on agent polls, at least two seconds apart.
It permits at most two reads at once and at least two seconds between reads for one agent.
Failed reads retry after 2, 4, 8, then 16 seconds at most for one revision.
A successful screen read or a new revision resets the delay to two seconds.
One main-thread timer retries pending reads after the delay. It stops when no retry remains.
The reader runs Herdr commands on a background queue.
