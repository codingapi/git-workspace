# repos-demo — 聚合工作区

用 [Google repo](https://gerrit.googlesource.com/git-repo/) 聚合管理多个 git 仓库的工程骨架。

## 快速开始

```bash
make setup    # = repo init + repo sync + 应用 sparse-checkout 规则
make sync     # 日常同步所有子仓库
make status   # 查看所有子仓库改动
```

## 目录结构与代码归属

| 路径 | 内容 | 谁管理 | 是否推送远端 |
|---|---|---|---|
| `/`(根) | 本地胶水代码:Makefile、README、scripts/ | 外层 git 仓库 | 自己决定 |
| `manifests/` | repo 清单(default.xml 等) | 独立 git 仓库 | 可单独推送共享 |
| `flow-engine/` | 后端(codingapi/flow-engine) | repo + 子仓库自身 | 上游仓库,改动走 PR |
| `flow-engine/web/` | 前端(codingapi/flow-frontend,排除 apps/docs) | repo + sparse-checkout | 同上 |
| `web2/` | 前端二次检出(仅 apps/docs) | repo + sparse-checkout | 同上 |
| `frameworks/fastjson2/` | 第三方库(alibaba/fastjson2) | repo | 只读引用,不推送 |
| `local/` | 个人本地试验代码 | 被 .gitignore | 永不入库 |
| `.repo/` | repo 元数据 | repo 自动生成 | 永不入库 |

## 在新机器复现

```bash
git clone <本仓库地址> repos-demo && cd repos-demo   # 拿到胶水代码
make setup                                          # 按清单拉取所有子仓库
```

> 共享给团队时:把 `manifests/` 推到独立 GitHub 仓库,
> 将 Makefile 里 `MANIFEST_URL` 改为该仓库地址即可。
