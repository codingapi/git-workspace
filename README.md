# repos-demo — 聚合工作区

用 [Google repo](https://gerrit.googlesource.com/git-repo/) 聚合管理多个 git 仓库。
布局完全由清单 `manifests/default.xml` **声明式**描述(含 linkfile 映射),无任何后置脚本。

## 快速开始

```bash
make setup    # = repo init + repo sync(linkfile 自动生成)
make sync     # 日常同步所有子仓库
make status   # 查看所有子仓库改动
```

## 目录结构与代码归属

| 路径 | 内容 | 本质 |
|---|---|---|
| `/`(根) | 本地胶水代码:Makefile、README | 外层 git 仓库(可不设 remote,纯本地) |
| `manifests/` | repo 清单(default.xml) | 独立 git 仓库,可单独推送共享 |
| `.sources/flow-frontend/` | 前端**唯一真实检出**(全量) | repo 管理的子仓库 |
| `flow-engine/` | 后端(codingapi/flow-engine) | repo 管理的子仓库 |
| `flow-engine/web/` | 前端视图:除 apps/docs 外的全部 | → `.sources/` 的 symlink(linkfile 生成) |
| `web2/` | 前端视图:仅 apps + docs | → `.sources/` 的 symlink(linkfile 生成) |
| `frameworks/fastjson2/` | 第三方库(alibaba/fastjson2) | repo 管理的子仓库,只读引用 |
| `.repo/` | repo 元数据 | 自动生成,永不入库 |

## 注意事项

1. **单一工作区语义**:`flow-engine/web`、`web2` 都是 `.sources/flow-frontend`
   这同一份检出的符号链接——同一个分支、同一份改动。在任一视图里编辑,
   `repo status` 都会显示在 `.sources/flow-frontend` 项目下。
2. **维护约定**:flow-frontend 上游新增顶层目录时,需在 `manifests/default.xml`
   补一行对应 `<linkfile>`,否则该目录不会出现在 `flow-engine/web` 视图中。
3. **嵌套 ignore**:`flow-engine` 里的 `web/` 目录通过 `make setup` 写入其
   `.git/info/exclude`(仅本地生效,不污染上游仓库)。

## 在新机器复现 / 共享给团队

```bash
git clone <本仓库地址> repos-demo && cd repos-demo   # 拿到胶水代码
make setup                                          # 按清单拉取全部子仓库
```

把 `manifests/` 推到独立 GitHub 仓库、并将 Makefile 里 `MANIFEST_URL`
改为该地址后,任何人一条 `make setup` 即可复现完整布局。
