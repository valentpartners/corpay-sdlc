---
name: get-pr-from-bitbucket
description: Resolve a Bitbucket PR reference (URL, id, or branch) to a numeric id and return its metadata, changed files, unified diff, and comment threads for the repo in .codex/aisdlc.json.
---

## Main Purpose
A read-only leaf for Bitbucket Server/DC. Given a PR reference, resolve it to a numeric id and fetch everything a caller needs to reason about the PR: metadata, changed files, the unified diff, and the full comment threads (with the data needed to reply to or resolve them later).

## Process

### 1. Load config
From `.codex/aisdlc.json`: `sourceControl.baseUrl`, `projectKey`, `repositorySlug`, and `apiTokenEnv` (the token env var, default `BITBUCKET_API_TOKEN`). All calls send `Authorization: Bearer $TOKEN`.

### 2. Resolve to a numeric id
- URL or explicit id → extract the numeric id.
- Branch name → list open PRs and match `fromRef.displayId` / `fromRef.id`.
- No input → list open PRs and pick with the human.

### 3. Fetch metadata, files, diff
```bash
B="$baseUrl/rest/api/latest/projects/$P/repos/$R/pull-requests/$ID"
curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" "$B"            # metadata
curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" "$B/changes?limit=200"
curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" "$B/diff"       # unified diff
```

### 4. Fetch comment threads
```bash
curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" "$B/activities?limit=100"
```
Paginate with `nextPageStart` until `isLastPage`. For each `COMMENTED` activity, flatten the root comment and its nested replies, capturing per root comment: `id`, `state`, `severity`, `author`, `commentAnchor` (path/line/lineType), reply text, and `version` (required to resolve a thread later).

## Rules
- **Work from the numeric id only** — never compose calls against an unparsed URL or branch.
- Read-only. This skill never posts, resolves, commits, or pushes.
- The PR branch is often already checked out in the application repo (`repositories.application`, e.g. `code/`).
