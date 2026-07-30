# 工作区投影层的一键入口(实际能力由 ./workspace 提供)

.PHONY: setup sync locked outdated status clean clean-all build-web

setup: ## 首次初始化:拉取全部源 + 物化 worktree + 建立投影
	./workspace sync

sync: ## 同步:更新缓存、重解析 revision、校正 worktree 与投影
	./workspace sync

locked: ## 严格同步:与 lock 不一致即失败(CI/团队成员用)
	./workspace sync --locked

outdated: ## 检查各源相对 lock 的漂移与上游新版本
	./workspace outdated

status: ## 查看源与投影状态
	./workspace status

clean: ## 删除 worktree 与投影(保留 git 缓存)
	./workspace clean

clean-all: ## 连 git 缓存一并删除(下次 sync 重新克隆)
	./workspace clean --all

build-web: ## 在前端装配位置安装依赖并构建核心包
	cd flow-engine/web && pnpm i && pnpm build:flow-core
