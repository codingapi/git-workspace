# One-stop entry points for the Workspace Projection Layer (real work done by ./git-workspace).
# Workspace targets operate on a local git-workspace.yaml — copy example.yaml to get started.

.PHONY: setup sync locked outdated status clean clean-all build-web install uninstall

setup: ## First-time init: fetch all sources + materialize worktrees
	./git-workspace sync

sync: ## Sync: update caches, re-resolve revisions, fix up worktrees and filters
	./git-workspace sync

locked: ## Strict sync: fail on any mismatch with the lock (CI / team members)
	./git-workspace sync --locked

outdated: ## Check each source for lock drift and newer upstream versions
	./git-workspace outdated

status: ## Show source and projection status
	./git-workspace status

clean: ## Remove worktrees (keeps the git cache)
	./git-workspace clean

clean-all: ## Remove worktrees and the git cache (next sync re-clones)
	./git-workspace clean --all

build-web: ## Example consumer command: install deps and build the core package at the frontend location
	cd flow-engine/web && pnpm i && pnpm build:flow-core

install: ## Install the git-workspace CLI (default prefix ~/.local; override with PREFIX=...)
	./install.sh

uninstall: ## Remove the installed git-workspace CLI
	./install.sh --uninstall
