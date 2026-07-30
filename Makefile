# 聚合工作区的一键入口
# 共享给团队时,把 MANIFEST_URL 改成 GitHub 上的清单仓库地址
MANIFEST_URL ?= file://$(CURDIR)/manifests

.PHONY: setup sync sparse status forall

setup: ## 首次初始化:按清单拉取所有仓库并应用稀疏检出
	repo init -u $(MANIFEST_URL) -b main -m default.xml
	repo sync -j8
	./manifests/scripts/setup-sparse.sh

sync: ## 同步所有子仓库
	repo sync -j8

sparse: ## 重新应用 sparse-checkout 规则
	./manifests/scripts/setup-sparse.sh

status: ## 查看所有子仓库的改动状态
	repo status

forall: ## 对所有子仓库执行命令,如 make forall CMD='git pull'
	repo forall -c '$(CMD)'
