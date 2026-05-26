# AISDLC workflow + skill catalog

The canonical reference for:
- **The AISDLC workflow** — the three-phase loop (Design → Implementation → Testing) for shipping features with Claude.
- **The skill catalog** — every active skill, in the glossary at the bottom.

Skills are self-contained leaf functions; this doc is the only place that explains *when* to activate them.

The manifest at `docs/ai-runs/{feature-slug}/manifest.yaml` is the **single source of truth** for story state. The runner reads it; phase skills read and write it.

## TL;DR

| Phase | Driver | Skills | Artefact at exit |
|-------|--------|--------|------------------|
| Design | Human, in chat | `grill-with-docs` ↔ `to-feature` (loop) → `to-feature-manifest` → `to-stories` | Sealed feature doc; manifest with vertical-slice stories; per-story `implementation.md` on disk. |
| Implementation | Runner script, autonomous | Runner spawns `implement-story` per eligible story | Per-story PR open against the feature integration branch; unit tests green; `run-summary` comment per agent run. |
| Testing | Human, in chat | `test-item` → preview → merge PR via GH UI (or `new-work-item` for follow-ups) | Story `done` in manifest; PR merged into integration branch. |

The feature integration branch ships into a protected branch (e.g., `stage`) as a single human-reviewed PR after every story is `done`. Worktree cleanup is `scripts/cleanup-worktrees.sh`, run once the feature is finished.

---

## Phase 1 — Design

- **Driver:** human, in chat.
- **Inputs:** an idea, conversation, or existing feature doc.
- **Skills:** `grill-with-docs` ↔ `to-feature` (loop until sealed) → `to-feature-manifest` → `to-stories`.
- **Artefacts:** sealed feature doc at `docs/features/{slug}.md`; manifest at `docs/ai-runs/{slug}/manifest.yaml`; per-story `implementation.md`.
- **Exit when:** every story is `ready-for-agent`, `needs-info`, or `ready-for-human`.

### `grill-me` (optional)
Lightweight adversarial dialogue — Claude pushes back to surface assumptions, edge cases, and trade-offs. No doc side effects.

### `grill-with-docs`
Adversarial dialogue — Claude pushes back to surface assumptions, edge cases, and trade-offs. Also updates repo documentation in-line:
- Updates `CONTEXT.md` inline as domain terms resolve.
- Offers ADRs when a decision meets the bar.
- Cross-references the codebase to spot intent/implementation drift.

### `to-feature`
Compacts the chat into a sealed feature doc at `docs/features/{slug}.md`. Re-run to merge new findings — the doc plateaus, it doesn't grow (synthesise-and-replace).

### `grill-with-docs` ↔ `to-feature` loop
- **Within one dev** — grill → compact → review → repeat until the doc captures a complete solution.
- **Across the team** — share the sealed doc; reviewers run `grill-with-docs` against it in fresh chats; updates go back through `to-feature`.
- **Move on when aligned** — once the team agrees, run `to-feature-manifest`.

### `to-feature-manifest`
Reads the sealed feature doc and drafts vertical-slice stories into `docs/ai-runs/{slug}/manifest.yaml`.

- Iterates with the human in chat; chat is the iteration surface, the manifest is the sealed output.
- Per-story fields: `id`, `title`, `description`, `covers`, `touches`, `validation`, `blocked_by`, `state`.
- Sticky IDs (`NNN-{short-slug}`); re-runs preserve in-flight states. New slices get `drafted`; removed slices get `wontfix` (never deleted).
- Confirmation mindset — does **not** re-open product or architectural decisions; hand back to `to-feature` if a design call is unsettled.
- On re-run, auto-focuses on any slice in `needs-info` first.

### `to-stories`
Loops through every `drafted` story in dependency order. Per story:
1. Explore subagent gathers feature-doc context, codebase verification, `.claude/rules/` bindings, traps.
2. Surface every concern, inconsistency, or open question to the human — one at a time. The "no surprises" bar: Phase 2 must be able to run hands-off.
3. Write `implementation.md` at `docs/ai-runs/{slug}/{story-id}/implementation.md`.
4. Flip the story's `state` to `ready-for-agent`.

If a slice is fundamentally wrong (e.g., should be split into two), `to-stories` flips it to `needs-info`, continues with independent slices, and exits. Re-invoke `to-feature-manifest` to revise the slice, then re-run `to-stories`.

`to-stories` never edits structural fields in the manifest — only `state`, plus the on-disk `implementation.md`.

---

## Phase 2 — Implementation

- **Driver:** `scripts/run-ai-loop.sh` (autonomous), spawning a fresh `claude` per story.
- **Inputs:** current branch (the feature integration branch); the manifest; per-story `implementation.md`.
- **Skills inside the spawned `claude`:** `implement-story`, `tdd`; sub-agents (`Explore`, `Validator`).
- **Owned by the runner (not the agent):** push, PR create/update, `run-summary` PR comment, manifest state flips, merge detection, worktree cleanup on `done`.
- **Exit when:** no story is eligible — either every reachable story is `pr-open` (awaiting human merge), or remaining stories are parked in `needs-info` / `ready-for-human`.

### The runner
```
bash scripts/run-ai-loop.sh                  # single-shot — process every eligible story, exit
bash scripts/run-ai-loop.sh --watch 300      # long-running — poll every 300s, pick up new work
```
Sequential per story; **non-blocking on PR merges** — the script keeps picking up independent stories while open PRs sit in human-review. Single instance only (lockfile at `.worktrees/.runner.lock`). Refuses to run from any branch in `branches.protected`.

### Each iteration
1. **Sync remote.** `git fetch`; `git pull` the integration branch if behind. For every story currently `pr-open`: check the linked PR — if merged, flip to `done`, remove the worktree and local branch.
2. **Pick.** Next eligible story:
   - `state: ready-for-agent` + all `blocked_by` are `done` (first run), OR
   - `state: pr-open` + all `blocked_by` are `done` + a fresh human PR comment exists newer than the latest agent `run-summary` (re-run from feedback), OR
   - `state: agent-dev` with an existing worktree (recovery from a crashed prior iteration — always re-spawn).
3. **Brief audit.** Confirm `implementation.md` is present in the runs dir. If missing, flip the story to `needs-info` and continue. Recovery: re-run `to-stories` for that story.
4. **Claim.** Flip `state` to `agent-dev`.
5. **Worktree.** Create `.worktrees/{story-id}/` off the integration branch if it doesn't exist; reuse on re-runs. Story branch: `{branches.prefix}{story-id}`.
6. **Context propagation.** Copy `docs/ai-runs/{slug}/{story-id}/` from the main tree into the worktree (the runs dir is gitignored, so `git worktree add` doesn't carry it).
7. **Compile prompt + spawn.** Thin prompt: story id, branch names, run number, diff caps, `large-diff-ok` flag, optional inlined PR-feedback bundle on re-runs. Ends with `Run /implement-story`. Spawn `claude --permission-mode acceptEdits -p --output-format stream-json --verbose` in the worktree, bounded by `caps.perStoryWallClockSec`.
8. **Post-agent gates.** Before any remote action, verify:
   - At least one new commit on the story branch since fork.
   - Each commit message references the story ID.
   - Diff within `caps.diffFiles` / `caps.diffLines` (skip if `large-diff-ok`).
   - `run-<n>.md` exists.
   - Worktree clean.
   - `claude` exited 0.

   One gate failure → flip to `needs-info`, log the named gate, leave the worktree intact, continue.
9. **Push + PR.** `git push -u origin {story-branch}`. On run 1, `gh pr create --base {integration} --head {story-branch}` with the structured body; capture PR number into the manifest entry's `pr:` field. On subsequent runs, the push updates the existing PR.
10. **Post run-summary.** Read `run-<n>.md`, prepend `## [Type: run-summary | by: scripts/run-ai-loop.sh | run <n>]`, post via `gh pr comment`.
11. **Flip state.** `state → pr-open`. Continue.

### Re-run semantics (feedback channel)
The human reviews the PR and leaves comments — issue-level, line-level, review summaries. **No state flip required.** The runner detects fresh feedback by **watermark**:
- The watermark is the most recent `## [Type: ...]` comment authored by the runner on the PR.
- Any comment from a `User`-type GitHub account newer than the watermark is a re-run signal. Bot comments (CI, dependabot, etc.) are ignored.

On a re-run pick, the runner bundles every post-watermark human comment into the spawn prompt:
- **General comments** — author, timestamp, body.
- **Line-level review comments** — grouped by file with `path`, `line`, `diff_hunk` showing the code context, body, threaded replies in chronological order.
- **Review summaries** — `APPROVE` / `REQUEST_CHANGES` / `COMMENT` with body.

Inlined verbatim. The agent re-reads `implementation.md` plus prior `run-<n>.md` files. The story stays `pr-open` throughout; the agent's new `run-summary` becomes the new watermark. GH's "resolved thread" state is ignored — only the watermark filter matters.

`implementation.md` stays **frozen** across re-runs. If the plan is fundamentally wrong, flip the story to `drafted` and re-run `to-stories`.

### Sub-agents inside the iteration

| Sub-agent | Job | Returns |
|-----------|-----|---------|
| Explore | Codebase tracing (find / grep / read) | Short summary of how X is done here |
| Validator | Build / test / lint | Compact pass/fail summary |

Authoring (planning, writing tests, writing code) stays with the parent agent.

### Observability — three log surfaces
- **Live stderr.** `claude`'s stream-json events piped through a `jq` formatter: one line per tool call, per turn, plus init / done events. What the human watches in real time.
- **Per-run stream-json** at `docs/ai-runs/{slug}/{story-id}/run-<n>.stream.jsonl` — full unparsed agent events. Post-mortem record for F1s.
- **Per-feature orchestration log** at `docs/ai-runs/{slug}/runner.log` — append-mode, timestamped. Script-side events (claim flips, gate checks, push, PR-create, merge detection, exit reasons). The "what did the harness do overnight?" narrative.

---

## Phase 3 — Testing

- **Driver:** human, in chat (with AI subagents).
- **Inputs:** a `pr-open` story with an open PR.
- **Skills:** `test-item` → preview → merge PR via GH UI (or `new-work-item` for follow-ups).
- **Artefacts:** test plan posted on the PR; testing summary on disk; PR merged into integration.
- **Exit when:** every story is `done` and the feature is ready for its integration → protected-branch PR.

### Chat 1 — `test-item`
1. Locate the story; read the manifest entry's `validation` bullets and any PR review comments.
2. Generate the full test plan inline (delegating codebase tracing to an Explore subagent for >5 changed files). Rows labelled AFK or HITL.
3. Run AFK rows via the headless UI driver subagent. Capture pass/fail.
4. For each fail — **in scope:** drive a fix in the worktree, push, regenerate the plan, loop. **Out of scope:** `new-work-item` for a follow-up.
5. Write a testing summary under the story dir.
6. Hand off to a fresh chat for the human UI walk.

### Context clear
Human clears context, opens a new chat in the story's worktree, loads the testing summary.

### Chat 2 — preview
Init-generated skill that brings up the local environment so the human drives the UI. Validates the worktree, parses the deploy spec, builds and runs services, prints URLs / PIDs / HITL rows / kill commands.

### Human walks the UI
Three outcomes:
- **Pass** → merge the PR via the GitHub UI (or `gh pr merge`). The runner detects the merge on its next iteration, flips `state → done`, removes the worktree + local branch, and unblocks any dependents.
- **File follow-up** → `new-work-item bug` (or `story`).
- **Iterate** → either pair with Claude in the worktree on small fixes (commit, keep preview running), OR post review comments on the PR and let the runner re-spawn the agent on its next iteration.

### Merge as the gate
The human merging the PR via the GitHub UI is the canonical "story complete" action — no separate skill to invoke. The runner is responsible for detecting the merge and flipping state. In `--watch` mode it picks up merges automatically; in single-shot mode the next invocation does the catch-up.

Once every story is `done`, the human opens the integration → protected-branch PR manually. That aggregate review stays strictly human-driven.

---

## Reference

### State vocabulary

State machine on each manifest story. Vocabulary is structural — defined here, not in config.

| State | Set by | Meaning |
|-------|--------|---------|
| `drafted` | `to-feature-manifest` | Slice exists on the manifest; no `implementation.md` yet. Runner ignores. |
| `needs-info` | `to-stories` at publish, or runner on F1 | Concrete missing info, or the agent gave up after the TDD cap. |
| `ready-for-agent` | `to-stories` once `implementation.md` is written | Fully specified; runner can pick up. |
| `agent-dev` | Runner only | Runner claimed the story; a `claude` process is working on it. Blocks dependents. |
| `pr-open` | Runner only | Agent opened the story PR; awaiting human review / merge. Blocks dependents. Re-runs triggered by PR comments. |
| `ready-for-human` | `to-stories` | Cannot be delegated. Judgment / external access / design call. |
| `wontfix` | `to-feature-manifest` (removed slice), or human | Will not be actioned. Terminal. |
| `done` | Runner on merge detection | Story PR merged into integration. The only state that unblocks dependents. |

Categories (exactly one): `bug`, `enhancement`. Override (zero or more): `large-diff-ok` exempts the story from the diff cap.

`agent-dev`, `pr-open`, and `done` are machine-managed — humans don't hand-flip them. To request another agent pass on a `pr-open` story, post a comment on the PR; the runner picks it up automatically.

### Branch naming
Configured prefix lives in `aisdlc.json` (`branches.prefix`). Default `claude/`.

| Branch | Pattern | Example |
|--------|---------|---------|
| Integration | human-chosen | `online-toggle` |
| Story | `{prefix}{story-id}` | `claude/001-product-type-enum` |

The integration branch is whatever you've checked out when you invoke the runner — pick a name that reads well in PRs.

### PR flow

```
Story branch  →  PR  →  integration branch  →  PR  →  protected branch
                  ^                              ^
            opened by runner               opened by human
            merged by human                merged by human
```

Story PRs always target the integration branch. The integration → protected-branch PR stays strictly manual — the runner refuses to open PRs against any branch in `branches.protected`.

### Bounded write surface
The runner is the only writer for:
- Story branches (`{branches.prefix}{story-id}`) — created, pushed, force-updated by the runner.
- The manifest's machine-managed states (`agent-dev`, `pr-open`, `done`) and the `pr:` field.
- PR comments carrying the `## [Type: ...]` header (`run-summary`, `agent-diagnostics`, `pre-run-audit`).

Everything else (integration branch, protected branch, design-time manifest fields, untyped PR comments, merges) is human-managed. Reads are unrestricted.

### Failsafes
- **Pre-run merge detection** — runner picks up a merged PR that was missed on a prior iteration, flips `done`, cleans up.
- **Brief existence audit** — runner hard-fails the iteration if `implementation.md` isn't in the worktree; recovery is re-running `to-stories`.
- **Post-agent gates** — commit count, story-ID references, diff cap, run-log presence, clean worktree, exit code 0. One gate failure → `needs-info`.
- **TDD attempt cap** (`caps.tddAttempts`) — agent gives up gracefully; gates catch it.
- **Diff cap** (`caps.diffFiles` / `caps.diffLines`) — override via `large-diff-ok`.
- **Per-story wall clock** (`caps.perStoryWallClockSec`) — runner kills the agent process if it's chewing too long.
- **Worktree isolation** — every story runs in its own worktree.
- **Single-runner lockfile** at `.worktrees/.runner.lock` — prevents concurrent invocations.
- **No automatic protected-branch merge** — humans always merge integration → protected.

### Setup checklist
One-time, when bootstrapping a new project from this scaffold:
1. Confirm `gh auth status` is green (runner uses `gh` for push + PR create + PR comment).
2. Install `yq` (manifest reads/writes) — `jq` and `git` are assumed present.
3. Run the init skill (forthcoming) to specialize for your stack. The init skill:
   - Activates the appropriate skills from `_inactive/` (build / test / lint family matching the chosen stack).
   - Adds stack-specific permissions and hooks to `.claude/settings.json`.

---

## Skill glossary

Alphabetical. Phase markers indicate AISDLC participation.

- [diagnose](diagnose/SKILL.md) — Disciplined diagnosis loop for hard bugs and performance regressions. *(forthcoming)*
- [grill-me](grill-me/SKILL.md) — Adversarial interview about a plan, design, or solution. *(forthcoming)*
- [grill-with-docs](grill-with-docs/SKILL.md) — `[phase 1]` Grill that challenges a plan against the domain model and updates `CONTEXT.md` / ADRs inline.
- [implement-story](implement-story/SKILL.md) — `[phase 2]` Implement one story end-to-end from its `implementation.md`. Ground, TDD, commit locally, write run log.
- [new-work-item](new-work-item/SKILL.md) — `[phase 3]` Create an ad-hoc story or bug.
- [review-pr](review-pr/SKILL.md) — Read pull requests and post comments.
- [tdd](tdd/SKILL.md) — Test-driven development.
- [test-item](test-item/SKILL.md) — `[phase 3]` Generate the test plan, run AFK rows, write the testing summary.
- [to-feature](to-feature/SKILL.md) — `[phase 1]` Compact a chat into a sealed feature doc.
- [to-feature-manifest](to-feature-manifest/SKILL.md) — `[phase 1]` Decompose a feature doc into a manifest of vertical-slice stories.
- [to-stories](to-stories/SKILL.md) — `[phase 1]` Per drafted story: explore, surface concerns, write `implementation.md`, promote.
- [write-a-skill](write-a-skill/SKILL.md) — Author or revise a SKILL.md. *(forthcoming)*
- [write-an-adr](write-an-adr/SKILL.md) — Author an ADR. *(forthcoming)*
- [zoom-out](zoom-out/SKILL.md) — Give broader context on an unfamiliar area of code.
