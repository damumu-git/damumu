# Coordinator contract

Own the user's outcome across API, App, Web, Admin and operations. Use one agent
for small/local edits. Use multiple agents when tasks have independent scope and
the user or repository policy authorizes delegation. Respect the host's available
agent slots and approval policies; this repository does not override them.

## Plan and context

Read AGENTS.md, PROJECT.md and current STATUS.md first. Verify Git state and
relevant ADRs against code. Create a task with tools/agent_workspace.py. Fill its
brief.md with outcome, exclusions, acceptance criteria, dependencies and a shared
API/data contract before dispatching. Allocate new migration numbers yourself.
Start with the minimum roles needed, at most three workers at once. Review runs
after implementation and does not consume a permanent worker slot.

Each worker receives a bounded packet containing task-specific goals, the pinned
base, path ownership, dependency names, canonical file fingerprints, reading
instructions, verification commands and a handoff template. Do not forward the
full chat by default. For Codex subagent tools, prefer a fresh context with the
packet; when the host cannot select a worker checkout, do read-only work there
and run writes in a separate session rooted at the generated worktree. Never
assume spawned agents automatically have isolated worktrees.

## Execution

Use `worktree` to prepare one branch/checkout per writer. Launch agents using the
host's native tools, or open their worktree in Codex and supply packet.md. The
Python helper manages context and Git state; it does not call a model or start
paid requests. Do not fabricate agent results when tools are unavailable.

Finish dependent API contracts before clients, or explicitly agree a stable
contract with fixtures. Workers do not independently edit canonical docs or
deploy. If overlapping work is necessary, serialize it or split explicit files.
Use unique test databases, container names and ports; all worktrees share Git
history and external services. Do not share ignored secrets.

## Integration gate

Collect handoffs and local commits. Run `check` for every worker; fix scope drift
or revise ownership explicitly. Check both committed and uncommitted changes.
Refresh stale packets and review the actual diff against the pinned base.
Cherry-pick reviewed worker commits sequentially onto the task integration branch
and resolve conflicts there; never automatically merge or delete worker branches.
Run cross-module validation on the combined result, then use a read-only reviewer.
Evidence must cover authorization boundaries, API compatibility, localization,
responsive UI and migrations where affected.

Only the coordinator updates STATUS.md and ADRs, reviews secrets, commits and
pushes the integration branch. Honor the user's merge/deployment authorization.
Advance server notification must list migration, backup, environment, restart,
credential and client-version effects. Report verified results, unverified
limits and next steps separately. Never equate a pushed branch with a release.
