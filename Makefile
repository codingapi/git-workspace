# 聚合工作区的一键入口
# 共享给团队时,把 MANIFEST_URL 改成 GitHub 上的清单仓库地址
MANIFEST_URL ?= file://$(CURDIR)/manifests

.PHONY: setup sync status forall

setup: ## 首次初始化:按清单拉取所有仓库(linkfile 由 repo 自动生成)
	repo init -u $(MANIFEST_URL) -b main -m default.xml
	repo sync -j8
	@# 嵌套的 web/ 在外层 flow-engine 里会显示未跟踪,本地忽略(不污染上游)
	@grep -q '^web/$$' flow-engine/.git/info/exclude 2>/dev/null || echo 'web/' >> flow-engine/.git/info/exclude

sync: ## 同步所有子仓库(linkfile 链接自动重建)
	repo sync -j8

status: ## 查看所有子仓库的改动状态
	repo status

forall: ## 对所有子仓库执行命令,如 make forall CMD='git pull'
	repo forall -c '$(CMD)'
