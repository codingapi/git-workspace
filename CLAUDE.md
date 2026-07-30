# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The source of **git-workspace**, a "Workspace Projection Layer" CLI: a declarative `git-workspace.yaml` assembles **real git worktrees** into a complete project tree. The entire engine is the single-file `./git-workspace` script (~800 lines of Python 3, depends only on PyYAML and the git CLI). This repo is the *software*, not an active workspace — `example.yaml` / `example.lock.yaml` are bundled sample data (to try them: `cp example.yaml git-workspace.yaml && ./git-workspace sync`; the assembled worktrees are gitignored artifacts).

## Commands

```bash
./git-workspace init            # scaffold git-workspace.yaml + .githooks/pre-commit + core.hooksPath in the CWD
./git-workspace sync            # fetch/update sources, materialize worktrees, refresh git filters, rewrite lock (= make setup / make sync)
./git-workspace sync --locked   # strict mode: fail if resolved SHAs differ from git-workspace.lock.yaml (CI / reproducibility)
./git-workspace status          # per-source SHA, dirty state, checkout filter, read-only lock state
./git-workspace outdated        # lock drift + upstream newer tags (fetches each cache first)
./git-workspace guard           # commit-protection check; invoked by the generated pre-commit hook
./git-workspace clean           # remove worktrees (--all also deletes .workspace/git-cache)
./git-workspace version         # print version (also -V/--version)
./install.sh [--prefix DIR] [--uninstall]   # install CLI to ~/.local/bin (Linux/macOS/Git-Bash); install.ps1 for native Windows
```

There is **no test suite**. Verify changes by running the CLI: `-h`, `version`, `init` in a scratch dir, and a `sync`/`status`/`clean` round-trip against `example.yaml` (network access to GitHub required).

## Architecture

### Workspace root resolution

The CLI works both in-repo (`./git-workspace`) and globally installed. `find_root()` walks **up from the CWD** until it finds `git-workspace.yaml`, then `init_paths(root)` binds the module globals (`ROOT`, `CONFIG_PATH`, `LOCK_PATH`, `DOT`, `CACHE`, `STATE_PATH`). Exceptions handled in `main()`: `version` needs no root; `init` operates on the CWD itself; `guard` is **lenient** — no config found → exit 0 (nothing to protect) rather than blocking commits.

### The three data layers

- `git-workspace.yaml` — declarative source list (checked in). Each source: `url`, `revision`, `path` (assembly location, may be nested), mutually-exclusive `include`/`exclude` checkout filters, optional `readonly`, optional `cache` key.
- `git-workspace.lock.yaml` — **generated** by sync: revision + resolved 40-char SHA per source. Checked in so `sync --locked` can reproduce exact snapshots. SHAs are force-quoted via the `_Quoted` YAML representer because all-digit SHAs would otherwise round-trip as integers.
- `.workspace/` (gitignored) — `git-cache/<key>.git` bare mirror clones and `state.json` (last-sync SHA/filter/readonly per source; `state.json`'s `sha` is the *sync baseline*, not the config).

### Two repo roles, one pipeline

`cmd_sync` runs two phases:

1. **Fetch + resolve** — every source is resolved against a mirror cache. `cache_key()` defaults to a slug of the URL, so multiple sources from the *same* URL (e.g. `fastjson2-core` / `fastjson2-ext`) automatically share one object store; the `fetched` set ensures one fetch per cache per sync. `--locked` validation happens after resolution, before any worktree is touched.
2. **Materialize** — sources ordered by path depth (parents first), each becoming a real detached worktree via `git worktree add` from the cache. Filtered sources use `--no-checkout` → `apply_filter` → `read-tree -mu HEAD` (the empty index from `--no-checkout` needs one materialization pass). `readonly` sources are chmod-locked (`set_locked`) after sync; sync itself is the only writer (unlock → checkout → relock).

### Checkout filters (`apply_filter`)

- `include` → `sparse-checkout set` in **cone** mode (directory whitelist; top-level files always kept).
- `exclude` → **non-cone** mode: `sparse-checkout set --no-cone '/*' '!/a/b'` (gitignore-style negation, supports nested paths).
- neither → `sparse-checkout disable`.

Filter changes between syncs are detected by comparing `source_filter()` against `state.json`, and trigger re-application.

### Auto-managed git filters and hooks — never hand-edit

`ensure_git_filters` writes **managed blocks** (`# git-workspace managed (begin/end)`) that are rewritten wholesale on every sync and are self-healing:

- outer repo's `.git/info/exclude` — ignores each assembly path (reduced to a `minimal_cover`, so nested paths aren't double-ignored) plus `/.workspace/`. Anything *not* under an assembly path is local code and is tracked by the outer repo automatically.
- parent worktree's `info/exclude` — located via `git rev-parse --git-common-dir` (linked worktrees keep exclude in the commondir, not the per-worktree dir) — ignores nested child sources like `flow-engine/web`.

Hooks are managed by `write_hook()`, which writes `.githooks/pre-commit` (created by `init`, rewritten by `ensure_hooks` on every sync; this repo tracks one such hook, dogfooding it — `guard` is lenient when no config exists, so it never blocks commits here). The hook prefers `git-workspace` from PATH and falls back to `./git-workspace`, then runs `guard`, which rejects staged files under any assembly path and any staged gitlinks (mode `160000`). Protected paths are computed dynamically from the config via `protected_paths()`.

### Safety gates (don't "simplify" these)

In `materialize_source`, when a worktree's HEAD ≠ target SHA, sync refuses if the tree is dirty or if HEAD is ahead of the **previous sync point** (`state.json` SHA) — deliberately *not* ahead of the target SHA, because switching between tags/branches means HEAD legitimately contains upstream commits the target lacks. `load_lock` defends against numeric-SHA corruption by rejecting any SHA that isn't exactly 40 chars.

### Config validation (`load_config`)

Enforced invariants a new source must satisfy: name matches `^[A-Za-z0-9][A-Za-z0-9._-]*$`; `include`/`exclude` mutually exclusive lists of path strings with no `..`; `path` not inside `RESERVED_TOPS` (`.git`, `.workspace`), not colliding with `RESERVED_FILES`, no duplicates; and **no source may be nested inside a `readonly` source**.
