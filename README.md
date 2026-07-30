# git-workspace

**English** | [中文](README.zh-CN.md)

git-workspace is a multi-repository workspace manager for git. You declare all
your repositories in one YAML file, and one command assembles them into a real
project tree — built from real git worktrees, no symlinks. Open the root in
your IDE and develop, build, and debug as usual.

## Features

- 📄 **One declarative config** — `git-workspace.yaml` describes every repo: URL, revision, where to place it
- 🌲 **A real directory tree** — assembled from git worktrees; IDE, pnpm, maven, and docker all see real paths
- 🔍 **Sparse checkouts** — `include`/`exclude` filters fetch only what you need
- 🔒 **Read-only dependencies** — third-party code is locked on disk; only `sync` can write it
- 📌 **Reproducible** — a lock file pins exact commit SHAs; `sync --locked` reproduces them exactly (CI-friendly)
- 🛡 **Commit protection** — a pre-commit hook stops third-party code leaking into your repo by accident
- 🚀 **Self-updating** — `git-workspace update` upgrades the CLI to the latest release

## How to use

### Install

Requires Python 3.8+, git, and PyYAML (the installers check/install PyYAML for you).
Standalone installs always pin the **latest release tag**, never the development branch.

**Linux / macOS / Git Bash:**

```bash
curl -fsSL https://raw.githubusercontent.com/codingapi/git-workspace/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/codingapi/git-workspace/main/install.ps1) }"
```

From a clone: `./install.sh` (`--prefix DIR` overrides the default `~/.local`).

### Set up a workspace

```bash
mkdir my-project && cd my-project && git init
git-workspace init          # creates git-workspace.yaml + commit-protection hooks
# edit git-workspace.yaml and declare your repositories
git-workspace sync          # fetches everything and assembles the tree
```

A minimal configuration:

```yaml
version: 1
sources:
  my-backend:
    url: git@github.com:example/my-backend.git
    revision: main
    path: my-backend                 # assembly location (may nest, e.g. my-backend/web)
  my-lib:
    url: git@github.com:example/my-lib.git
    revision: v1.0.0
    path: libs/my-lib
    include: [core]                  # check out only core/
    readonly: true                   # lock it on disk
```

Then work directly inside the assembled tree. Any directory you haven't
declared (e.g. `app/`) is tracked by your outer git repo as usual — no manual
`.gitignore` configuration needed.

This repository ships a runnable demo: `cp example.yaml git-workspace.yaml &&
git-workspace sync` assembles a backend repo, a nested frontend repo, and two
filtered read-only checkouts of the same third-party library.

## Uninstall

**Linux / macOS / Git Bash:**

```bash
curl -fsSL https://raw.githubusercontent.com/codingapi/git-workspace/main/install.sh | sh -s -- --uninstall
```

**Windows (PowerShell):**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/codingapi/git-workspace/main/install.ps1) } -Uninstall"
```

Installed from a clone? Re-run `./install.sh --uninstall`.
To also remove a workspace's worktrees and caches first: `git-workspace clean --all`.

## Common commands

| Command | Description |
|---|---|
| `git-workspace init` | Create a starter config + commit-protection hooks in the current directory |
| `git-workspace sync` | Fetch sources, materialize worktrees, refresh the lock |
| `git-workspace sync --locked` | Reproduce the exact locked SHAs; config must match the lock; lock is not rewritten (CI) |
| `git-workspace status` | Per-source SHA, dirty state, checkout filters, read-only state |
| `git-workspace outdated` | Check lock drift and newer upstream tags |
| `git-workspace verify` | Integrity check for CI: sources match the lock, read-only sources clean and locked (non-zero exit on failure) |
| `git-workspace update` | Self-update to the latest release |
| `git-workspace clean [--all]` | Remove worktrees (`--all` also clears the object caches) |
| `git-workspace version` | Print the version (also `-V` / `--version`) |

`git-workspace guard` runs inside the pre-commit hook; you rarely call it
yourself. A `Makefile` wraps the common commands (`make sync`, `make status`,
`make install`, …).

## Core components & how it works

```
git-workspace.yaml ──▶ engine ──▶ .workspace/git-cache/      (mirror clones, shared per URL)
                          │                 │
                          ▼                 ▼
             git-workspace.lock.yaml   real worktree at each source path
                          +        managed git filters & pre-commit hook
```

- **The engine** — `git-workspace` itself: a single-file Python CLI (~850
  lines) that depends only on git and PyYAML. It parses the config, orders the
  work, and delegates every heavy operation to native git (mirror clone,
  worktree, sparse-checkout, revision resolution).
- **Two repo roles** — development repos are checked out in full and stay
  editable where your product lives; consumed dependencies get checkout
  filters plus a filesystem-level read-only lock, and the tool is their only
  writer — `sync` refuses to run against a modified read-only source and
  `verify` flags one. The lock is an anti-accident guardrail (POSIX permission
  bits; the read-only file attribute on Windows), not a security boundary —
  for tamper-proof CI inputs use a read-only mount and read-only credentials.
- **Mirror cache** — bare clones under `.workspace/git-cache/`, keyed by URL,
  so multiple sources from the same repository share one object store and are
  never downloaded twice.
- **Lock file** — `sync` resolves each revision to a SHA and writes
  `git-workspace.lock.yaml`. Commit it, and anyone (or CI) reproduces the
  exact tree with `sync --locked`: in that mode the engine checks out the
  *locked* SHA verbatim (a floating revision like `main` advancing upstream is
  ignored), requires the config's source set, `url` and `revision` to match the
  lock, and never rewrites it. `verify` then asserts the materialized tree
  matches the lock and that read-only sources are clean and locked.
- **Workspace root discovery** — the CLI walks up from the current directory
  to find `git-workspace.yaml`, so it behaves identically whether installed
  globally or run from a clone.
- **Managed git filters** — every sync rewrites marked blocks in the repos'
  exclude files (self-healing): assembly paths are ignored by the outer repo,
  and everything undeclared is tracked as usual.
- **Safety** — sync refuses to overwrite uncommitted work or local commits;
  the `guard` hook blocks force-adding assembly directories or embedded git
  repositories into the outer repo.
- **Release channel** — installers pin the latest release tag, and
  `git-workspace update` compares your version against it and upgrades in
  place.

## Contributing

Development needs nothing but Python 3, PyYAML, and git — run the CLI straight
from the clone:

```bash
git clone git@github.com:codingapi/git-workspace.git && cd git-workspace
./git-workspace -h
# end-to-end smoke test against the bundled example:
cp example.yaml git-workspace.yaml && ./git-workspace sync && ./git-workspace status
./git-workspace clean --all && rm git-workspace.yaml git-workspace.lock.yaml
```

Guidelines:

- Keep the single-file design — the entire engine is `git-workspace`; no build step, stdlib + PyYAML only.
- Keep it declarative — new capabilities belong in `git-workspace.yaml`, not in flags.
- There is no test suite yet — verify changes with the smoke test above and `git-workspace -h`.
- Releases: bump `__version__` → commit → `git tag v<version>` → push the tag; installers and `update` pick it up automatically.

Issues and pull requests: https://github.com/codingapi/git-workspace
