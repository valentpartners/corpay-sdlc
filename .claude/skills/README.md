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
| Build & Validate | Runner (autonomous) + human (in chat, per story) | Per story: runner spawns `implement-story` → human runs `preview` → merges PR. After all `done`: `cleanup-worktrees.sh` → `to-qa-handoff` | Every story merged into integration; per-story `testing.md` on disk; QA handoff doc sealed; integration PR ready to open. |

The feature integration branch ships into a protected branch (e.g., `stage`) as a single human-reviewed PR after every story is `done`, the cleanup script has run, and the QA handoff doc is sealed.

---

## Phase 1 — Design

**What you do:**
- Iterate with Claude (`grill-with-docs`) until the design captures problem, product behavior, and architecture.
- Compact the chat into a sealed feature doc (`to-feature`); loop with `grill-with-docs` until the team is aligned.
- Decompose into vertical-slice stories on the manifest (`to-feature-manifest`).
- Per drafted story (`to-stories`): surface concerns, write `implementation.md`, promote to `ready-for-agent`.

**End state:** sealed feature doc, story manifest, per-story `implementation.md` files on disk. Phase 2 can run hands-off from here.

### Details
- **Driver:** human, in chat.
- **Inputs:** an idea, conversation, or existing feature doc.
- **Skills:** `grill-with-docs` ↔ `to-feature` (loop until sealed) → `to-feature-manifest` → `to-stories`.
- **Artefacts:** sealed feature doc at `docs/features/{slug}.md`; manifest at `docs/ai-runs/{slug}/manifest.yaml`; per-story `implementation.md`.
- **Exit when:** every story is `ready-for-agent`, `needs-info`, or `ready-for-human`.

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

## Phase 2 — Build & Validate

**What you do:**
- Kick off the runner — it picks up DAG-eligible stories from the manifest and implements them autonomously in their own worktrees.
- Per `pr-open` story: open a fresh chat in its worktree and run `preview`. Env boots, AFK Playwright runs in parallel, chat narrates HITL flows for you to walk.
- Iterate on findings — either pair with Claude in the preview chat, or drop a PR comment for the runner to re-spawn the implement agent. Mix freely.
- Merge the story PR via GitHub when validated. The runner unblocks DAG children; you move to the next `pr-open` story while the runner keeps building independent ones.
- When every story is `done`: run `cleanup-worktrees.sh`, invoke `to-qa-handoff`, then open the integration → protected-branch PR.

**End state:** every story merged into integration; per-story `testing.md` on disk; `qa-handoff.md` sealed; integration PR ready to open.

### Details
- **Drivers:** runner (`scripts/run-ai-loop.sh`, autonomous) + you (in chat, per story). Concurrent — runner advances DAG-independent work while you test.
- **Inputs:** sealed feature doc, manifest, per-story `implementation.md` from Phase 1.
- **Skills:** `implement-story` (inside runner-spawned `claude`), `preview` (you, per story), `to-qa-handoff` (you, end-of-feature). Out-of-scope findings dispatch via `new-work-item`.
- **Artefacts:** per-story PRs merged, `testing.md` per story, `qa-handoff.md` per feature.
- **Exit when:** every story is `done` (or `wontfix`), cleanup ran, `qa-handoff.md` sealed.

### Boot the runner

```bash
bash scripts/run-ai-loop.sh                  # single-shot — process every eligible story, exit
bash scripts/run-ai-loop.sh --watch 300      # long-running — poll every 300s, pick up new work
```

Sequential per story; **non-blocking on PR merges** — keeps picking up independent stories while open PRs sit in human-review. Single instance only (lockfile at `.worktrees/.runner.lock`). Refuses to run from any branch in `branches.protected`.

See [Runner internals](#runner-internals) for iteration mechanics, gates, and re-run semantics.

### Per story — `preview`

`preview` is init-generated, stack-specialized. One skill, one chat, in the story's worktree. Tracer-bullet design — every vertical slice has a user-visible surface, so every story walks through this flow.

1. **Boot env (subagent A).** Build and run services + portals. Print URLs, PIDs, kill commands. *While the env is booting, you can review the PR in GitHub and drop comments — those become a runner re-spawn signal (see step 4, PR-comment path).*
2. **AFK Playwright (`playwright-tester` subagent, parallel).** Explore the diff → callers → user-visible flows. Pick up to `caps.afk.maxFlows` flows within `caps.afk.wallClockSec` budget. The `playwright-tester` agent (defined at `.claude/agents/playwright-tester.md`) drives each flow via `playwright-cli` headless, throwaway DOM assertions, no test files written. Runs as a dedicated test user provisioned at boot. Reports pass/fail per flow inline — for each failed flow, also reports which changed file(s) the flow exercised so you can judge in-scope vs pre-existing in seconds.
3. **Narrate HITL (main chat).** From the story's `validation` bullets + diff, Claude tells you which flows to walk in your own browser. AFK results stream in alongside.
4. **Iterate** per finding:
   - **Out of scope?** Invoke `new-work-item` for a follow-up. Move on.
   - **In scope?** Pick a feedback channel — mix freely:
     - **In-chat pairing** — ask Claude here; commits + push happen in the worktree; hot-reload picks up. Fast loop.
     - **PR comment** — the runner re-spawns the implement agent on its next iteration; agent commits to the same worktree; hot-reload picks up too. Best for big changes.
5. **Append `testing.md` inline.** Throughout the session, Claude appends to `docs/ai-runs/{slug}/{story-id}/testing.md`: AFK flows + results, HITL prompts narrated, your feedback, commit SHAs of in-chat fixes. The chat may die; the file is the record (and the input to `to-qa-handoff` later).
6. **Merge.** When satisfied, merge the PR via the GitHub UI (or `gh pr merge`). The runner detects the merge on its next iteration, flips `state → done`, leaves the worktree + branch in place for cleanup.

### Working alongside the runner

Phase 2 is concurrent by design. The runner advances DAG-independent stories in their own worktrees while you test an already-implemented story in another.

| You are doing... | Runner is doing... |
|------------------|---------------------|
| Walking preview for story 001 | Implementing story 002 (DAG-independent) |
| Iterating in chat on 001 | (no new feedback after watermark on 002) |
| Merging 001 | Detects merge on next iteration → flips `done`, picks up 003 |

Two real constraints:
- **Runner cadence isn't instant.** `--watch 300` polls every 5 minutes; the agent spawn itself runs for 10–30 minutes. PR-comment feedback shows up in your worktree after that window. During the wait, keep walking parts of preview unrelated to the comment, or open a fresh chat in another `pr-open` story's worktree.
- **DAG depth caps concurrency.** Wide DAGs let the runner stay busy. Deep linear DAGs serialize to your merge cadence.

**Worktrees pile up by design.** Every `done` story's worktree (and the `testing.md` written there) stays until `cleanup-worktrees.sh` runs at end-of-feature. This protects testing artefacts from being lost and keeps the env bootable in case QA flags something later.

### End-of-feature — `cleanup-worktrees.sh` → `to-qa-handoff`

Once every story is `done` (or `wontfix`):

1. **Run the cleanup script** from the integration branch:
   ```bash
   bash scripts/cleanup-worktrees.sh
   ```
   For each `done` story: rsync `docs/ai-runs/{slug}/{story-id}/` from the worktree → integration's main tree (still gitignored — physically present, not committed), then `git worktree remove` + `git branch -D`. Bails if any non-`done` story still has a worktree.

2. **Invoke `to-qa-handoff`** in a fresh chat from the integration branch. Reads the feature doc's `<product-behavior>` Flows, all per-story `testing.md` files, and the manifest. Synthesizes into `docs/ai-runs/{slug}/qa-handoff.md` — page-organized (by user-facing route, not by story), with per-page checklists and named end-to-end scenarios. Iterates with you in chat; chat is the iteration surface, the doc is the sealed output.

3. **Open the integration → protected-branch PR** manually. Reference `qa-handoff.md` in the PR description for downstream QA distribution.

### QA findings — advisory, not blocking

QA is advisory. You own the integration → protected merge. QA findings loop back through `new-work-item` → new story on the manifest → runner picks it up → implement → test cycle → re-run `to-qa-handoff` to refresh. Teams without a formal QA function can skip handoff generation entirely.

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
| `done` | Runner on merge detection | Story PR merged into integration. The only state that unblocks dependents. Worktree + local branch persist until `cleanup-worktrees.sh` runs at end-of-feature. |

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
- Story branches (`{branches.prefix}{story-id}`) — created, pushed, force-updated by the runner. Deleted by `cleanup-worktrees.sh`, not by the runner.
- The manifest's machine-managed states (`agent-dev`, `pr-open`, `done`) and the `pr:` field.
- PR comments carrying the `## [Type: ...]` header (`run-summary`, `agent-diagnostics`, `pre-run-audit`).

The cleanup script (`scripts/cleanup-worktrees.sh`) is the sole writer for:
- Worktree teardown (`git worktree remove`).
- Local story-branch deletion (`git branch -D`).
- Copy-back of `docs/ai-runs/{slug}/{story-id}/` from each worktree → integration's main tree (gitignored, working-tree only).

Everything else (integration branch, protected branch, design-time manifest fields, untyped PR comments, merges, `testing.md` and `qa-handoff.md` content) is human-managed (or human-with-Claude in chat). Reads are unrestricted.

### Failsafes
- **Pre-run merge detection** — runner picks up a merged PR that was missed on a prior iteration, flips `done`, cleans up.
- **Brief existence audit** — runner hard-fails the iteration if `implementation.md` isn't in the worktree; recovery is re-running `to-stories`.
- **Post-agent gates** — commit count, story-ID references, diff cap, run-log presence, clean worktree, exit code 0. One gate failure → `needs-info`.
- **TDD attempt cap** (`caps.tddAttempts`) — agent gives up gracefully; gates catch it.
- **Diff cap** (`caps.diffFiles` / `caps.diffLines`) — override via `large-diff-ok`.
- **Per-story wall clock** (`caps.perStoryWallClockSec`) — runner kills the agent process if it's chewing too long.
- **Worktree isolation** — every story runs in its own worktree.
- **Worktree retention through `done`** — runner does not tear down on merge; `testing.md` and runs/ artefacts survive into end-of-feature cleanup. `cleanup-worktrees.sh` is the sole teardown path and bails on any non-`done` story with a worktree.
- **Single-runner lockfile** at `.worktrees/.runner.lock` — prevents concurrent invocations.
- **No automatic protected-branch merge** — humans always merge integration → protected.

### Setup checklist
One-time, when bootstrapping a new project from this scaffold:
1. Confirm `gh auth status` is green (runner uses `gh` for push + PR create + PR comment).
2. Install `yq` (manifest reads/writes) — `jq`, `git`, and `rsync` are assumed present.
3. Run the init skill (forthcoming) to specialize for your stack. The init skill:
   - Activates the appropriate skills from `_inactive/` (build / test / lint family matching the chosen stack).
   - Adds stack-specific permissions and hooks to `.claude/settings.json`.

### Runner internals

Mechanical detail for debugging the runner. Not needed for day-to-day shipping.

#### Each iteration

1. **Sync remote.** `git fetch`; `git pull` the integration branch if behind. For every story currently `pr-open`: check the linked PR — if merged, flip to `done`. Leave the worktree and local branch in place — `cleanup-worktrees.sh` handles teardown at end-of-feature.
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

#### Re-run semantics (PR-comment feedback channel)

The human reviews the PR and leaves comments — issue-level, line-level, review summaries. **No state flip required.** The runner detects fresh feedback by **watermark**:
- The watermark is the most recent `## [Type: ...]` comment authored by the runner on the PR.
- Any comment from a `User`-type GitHub account newer than the watermark is a re-run signal. Bot comments (CI, dependabot, etc.) are ignored.

On a re-run pick, the runner bundles every post-watermark human comment into the spawn prompt:
- **General comments** — author, timestamp, body.
- **Line-level review comments** — grouped by file with `path`, `line`, `diff_hunk` showing the code context, body, threaded replies in chronological order.
- **Review summaries** — `APPROVE` / `REQUEST_CHANGES` / `COMMENT` with body.

Inlined verbatim. The agent re-reads `implementation.md` plus prior `run-<n>.md` files. The story stays `pr-open` throughout; the agent's new `run-summary` becomes the new watermark. GH's "resolved thread" state is ignored — only the watermark filter matters.

`implementation.md` stays **frozen** across re-runs. If the plan is fundamentally wrong, flip the story to `drafted` and re-run `to-stories`.

#### Sub-agents inside the iteration

| Sub-agent | Job | Returns |
|-----------|-----|---------|
| Explore | Codebase tracing (find / grep / read) | Short summary of how X is done here |
| Validator | Build / test / lint | Compact pass/fail summary |

Authoring (planning, writing tests, writing code) stays with the parent agent.

#### Observability — three log surfaces
- **Live stderr.** `claude`'s stream-json events piped through a `jq` formatter: one line per tool call, per turn, plus init / done events. What the human watches in real time.
- **Per-run stream-json** at `docs/ai-runs/{slug}/{story-id}/run-<n>.stream.jsonl` — full unparsed agent events. Post-mortem record for F1s.
- **Per-feature orchestration log** at `docs/ai-runs/{slug}/runner.log` — append-mode, timestamped. Script-side events (claim flips, gate checks, push, PR-create, merge detection, exit reasons). The "what did the harness do overnight?" narrative.

---

## Skill glossary

Alphabetical. Phase markers indicate AISDLC participation.

- [grill-with-docs](grill-with-docs/SKILL.md) — `[phase 1]` Grill that challenges a plan against the domain model and updates `CONTEXT.md` / ADRs inline.
- [implement-story](implement-story/SKILL.md) — `[phase 2]` Implement one story end-to-end from its `implementation.md` (runs inside the runner-spawned `claude`). Ground, TDD, commit locally, write run log.
- [new-work-item](new-work-item/SKILL.md) — `[phase 2]` Create an ad-hoc story or bug.
- [preview](preview/SKILL.md) — `[phase 2]` Boot env, run AFK Playwright in parallel, narrate HITL flows in chat, append `testing.md`.
- [review-pr](review-pr/SKILL.md) — Read pull requests and post comments.
- [tdd](tdd/SKILL.md) — Test-driven development.
- [to-feature](to-feature/SKILL.md) — `[phase 1]` Compact a chat into a sealed feature doc.
- [to-feature-manifest](to-feature-manifest/SKILL.md) — `[phase 1]` Decompose a feature doc into a manifest of vertical-slice stories.
- [to-qa-handoff](to-qa-handoff/SKILL.md) — `[phase 2]` Synthesize per-story `testing.md` + feature doc's `<product-behavior>` into a page-organized QA distribution doc at the feature level.
- [to-stories](to-stories/SKILL.md) — `[phase 1]` Per drafted story: explore, surface concerns, write `implementation.md`, promote.
- [write-a-skill](write-a-skill/SKILL.md) — Author or revise a SKILL.md to match this scaffold's conventions.
- [zoom-out](zoom-out/SKILL.md) — Give broader context on an unfamiliar area of code.
