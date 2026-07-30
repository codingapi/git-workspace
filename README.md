# git-workspace — Workspace Projection Layer

A layer between Git and your build system: one declarative `git-workspace.yaml`
automatically assembles a **real project tree**.

## Core model: repositories come in two roles

- **Development repos** (flow-engine, flow-frontend) — parts of your product.
  Real git worktrees assembled directly at their logical project locations.
  **Open the workspace root in your IDE; develop, build and debug all happen
  in real directories** — no symlink problems for pnpm/maven/docker;
- **Consumed dependencies** (fastjson2) — read-only inputs. Real worktrees +
  checkout filters (include/exclude) + a filesystem-level read-only lock; the
  only writer is the sync tool.

There are **no symlinks anywhere** in the workspace — the assembled tree is
all real directories. IDE, pnpm, maven and docker all work on real paths,
with no split between logical paths and realpath.

```
git-workspace.yaml ──▶ projection engine ──▶ real worktrees (assembly locations)
                            │
             fetch / lock / filter / worktree / guard / git filters
```

## Directory layout

```
workspace/
├── flow-engine/            ← real worktree: backend (run mvn here)
│   └── web/                ← real worktree: frontend, nested assembly (run pnpm here)
├── frameworks/fastjson2-*  ← real worktrees: include filter + read-only lock (same repo, two places)
├── app/ deploy/ tests/     ← your own local code (example names; tracked by the outer git automatically)
├── .workspace/git-cache/   ← bare/mirror object caches (worktrees share objects)
├── git-workspace.yaml      ← declarative config (checked in)
└── git-workspace.lock.yaml ← commit SHA lock snapshot (checked in → exact team reproduction)
```

## Install

Requires: Python 3.8+, git, PyYAML (the installers check / install PyYAML for you).

**Linux / macOS / Windows Git-Bash:**

```bash
git clone git@github.com:codingapi/git-workspace.git
cd git-workspace
./install.sh                  # installs to ~/.local/bin (override with --prefix DIR)
./install.sh --uninstall      # remove it
```

**Windows (native, PowerShell):**

```powershell
git clone git@github.com:codingapi/git-workspace.git
cd git-workspace
powershell -ExecutionPolicy Bypass -File install.ps1        # adds git-workspace to your user PATH
powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
```

On Windows the read-only lock maps to the read-only file attribute (still
effective — Python's `os.access(W_OK)` honors it).

## Commands

```bash
git-workspace init            # scaffold a starter git-workspace.yaml + commit-protection hooks
git-workspace sync            # or: make setup / make sync
git-workspace sync --locked   # strict mode: fail on any mismatch with the lock (CI / team reproduction)
git-workspace status          # source SHAs, dirty state, checkout filters, read-only state
git-workspace outdated        # newer upstream tags? lock drift?
git-workspace guard           # commit-protection check (called by the pre-commit hook)
git-workspace clean           # tear down worktrees (--all also removes the git cache)
git-workspace version         # print version
```

## Trying the example

This repo ships `example.yaml` (plus `example.lock.yaml`, a sample of the
generated lock). To see the engine assemble a real multi-repo tree:

```bash
cp example.yaml git-workspace.yaml
git-workspace sync
git-workspace status
git-workspace clean --all     # tear it all down again
```

## git-workspace.yaml syntax

```yaml
version: 1

sources:
  <name>:
    url: <git url>
    revision: <branch | tag | SHA>     # resolved to a SHA in the lock on sync
    path: <assembly location>          # may nest (e.g. flow-engine/web); default = source name
    include: [<dir>...]                # optional whitelist: check out only these dirs (cone mode, git-recommended; top-level files always kept)
    exclude: [<path>...]               # optional blacklist: check out everything else (non-cone mode, supports nested paths like a/b/c)
    # include and exclude are mutually exclusive; neither = full checkout
    readonly: true                     # optional, filesystem-level read-only (recommended for third-party deps)
    cache: <cache name>                # optional explicit mirror cache key; defaults to keying by URL, same url shares automatically
```

**Same repo assembled in multiple places**: several source entries with the
same url = multiple independent worktrees (each with its own
filter/read-only/HEAD); objects automatically share one mirror cache — no
duplicate downloads. This is native git worktree semantics. Different
revisions of the same repo can coexist this way too. Each entry's `path` is
the assembly location and `include`/`exclude` the checkout filter; the
combination = "take this content, put it there".

**Two boundaries of filtering**:
- `include` (cone) is directory-granular; `exclude` (non-cone) supports
  nested paths and is backed by gitignore-style negation patterns — slightly
  slower than cone, and git officially notes its behavior may evolve. Prefer
  include; use exclude for "everything except a few dirs" cases;
- pruning **never deletes directories containing untracked files** (e.g. an
  installed node_modules) — that's git's data protection; tracked content is
  pruned as usual. If non-filtered paths reappear after a merge/rebase,
  `git-workspace sync` re-applies the filters automatically.

## Usage rules

1. **Develop directly in the assembled tree** — it's all real directories:
   open the root in your IDE, `mvn` → `flow-engine/`, `pnpm` →
   `flow-engine/web/`; docker builds use the workspace root as context and
   COPY points at real paths like `flow-engine/...`.
2. **Git filtering is fully automatic — configure no ignores yourself**: from
   the assembly paths in the yaml, the engine writes "managed blocks" (marked,
   rewritten wholesale on every sync, self-healing) into the outer repo's and
   parent worktrees' exclude files. **Any directory that is not an assembly
   path is local code, tracked by the outer git automatically** — create
   `app/` and commit it right away; an assembly path nested deep inside local
   dirs (e.g. `app/vendor/lib`) is still ignored precisely. Nested assembly
   (e.g. `flow-engine/web`) is ignored via the parent repo's managed block,
   without polluting the parent's status.
3. **Put local code in plain directories at the workspace root** (e.g.
   `app/`, `deploy/`, `tests/`) — edit, commit and build normally. Don't put
   it inside assembly directories — those are other repos' git worktrees.
4. **Check the lock in**: commit `git-workspace.lock.yaml`; teammates
   `git clone` + `git-workspace sync --locked` reproduce exactly. Upgrade =
   change revision → sync → verify → commit config and lock together (an
   explicit event, no drift).
5. **Nested assembly**: `path` may sit inside another source (e.g.
   `flow-engine/web`); the engine handles parent-repo ignores automatically.
   Nesting inside a read-only source is forbidden.

## Read-only and commit protection

- **Read-only locking**: sources with `readonly: true` are chmod-locked after
  sync — edits/creates/deletes all fail with `Permission denied`; even
  `rm -rf` can't delete them. Teardown goes through `git-workspace clean`
  (auto-unlocks). The only writer is `git-workspace sync` itself (unlock on
  sync, relock when done — the Nix store idea). Send third-party changes
  upstream via PR.
- **Sync safety gate**: if a source has uncommitted changes or local commits
  since its last sync point, sync refuses to overwrite and tells you where to
  sort it out.
- **Commit protection**: `.githooks/pre-commit` → `git-workspace guard`,
  computing protected paths dynamically from git-workspace.yaml (all assembly
  paths, exact match); blocks `git add -f` force-adds and embedded git repos
  (gitlinks). `git-workspace sync` sets `core.hooksPath` automatically, so
  every clone is protected out of the box.
- **Outer repo scope**: config, lock, docs, tooling, local code directories —
  the workspace's "definition, documentation and in-house parts", never any
  third-party source.

## Version management: a three-layer model

| Layer | What it manages | Managed by | How to upgrade |
|---|---|---|---|
| **Source versions** | which snapshot of each dependency repo | `revision` (readable tag) in git-workspace.yaml + exact SHAs in `git-workspace.lock.yaml` | explicit bump commit |
| **Product version** | the aggregate's overall version number | the outer repo's own git tags | release = tag (the lock at tag time = the full BOM) |
| **Ecosystem-internal versions** | version numbers inside each source's pom/package.json | each ecosystem's tools | follows the source snapshot bump automatically — never touch by hand |

Release semantics: the lock at outer tag v1.0.0 pins every source SHA →
`git checkout v1.0.0 && git-workspace sync --locked` reproduces the exact
source combination, then `mvn package` / `pnpm build` yields the artifacts.
Number maintenance: backend uses maven `${revision}` (CI-friendly versions),
frontend uses `pnpm -r` coordinated bumps.

## Relationship with git

Git is natively a single-repo tool; multi-repo aggregation is outside its
scope. In this scheme all the "heavy lifting" (mirror, worktree,
sparse-checkout, rev-parse) is native git capability — the engine (~800 lines
of Python) does just three things: parse declarations, schedule the loop,
execute policy. The engine depends only on git's stable CLI surface; the real
assets are the declarative yaml and the lock — platform-independent,
reproducible by any language or tool.
