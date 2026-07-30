# Workspace Projection Layer(工作区投影层)

在 Git 与构建系统之间的一层:一份声明式 `workspace.yaml`,自动装配出
**真实的工程树** + 可选的只读视窗。

## 核心模型:仓库分两种角色

- **开发型仓库**(flow-engine、flow-frontend)——工程的组成部分。真实 git
  worktree 直接装配在工程的逻辑位置上。**IDE 打开工作区根目录,开发、构建、
  调试都在真实目录里发生**,pnpm/maven/docker 无 symlink 问题;
- **消费型依赖**(fastjson2)——只读输入。真实 worktree + sparse 稀疏检出
  + 文件系统级只读锁,唯一写入者是同步工具;
- **视窗 views**——symlink。把某仓库的子目录曝光到方便的位置(web2 =
  apps + docs)。**只看不跑:不要在里面执行任何构建**。

```
workspace.yaml ──▶ 投影引擎 ──▶ 真实 worktree(装配位置)+ symlink 视窗
                     │
        fetch / lock / sparse / worktree / guard
```

## 目录结构

```
workspace/
├── flow-engine/            ← 真实 worktree:后端(mvn 在这里执行)
│   └── web/                ← 真实 worktree:前端,嵌套装配(pnpm 在这里执行)
├── frameworks/fastjson2/   ← 真实 worktree:sparse core + 只读锁定
├── web2/                   ← symlink 视窗:apps + docs(仅供浏览)
├── app/ deploy/ tests/     ← 本地自己的代码(示例名;外层 git 跟踪)
├── .workspace/git-cache/   ← bare/mirror 对象缓存(worktree 共享 objects)
├── workspace.yaml          ← 声明式配置(入库)
└── workspace.lock.yaml     ← commit SHA 锁定快照(入库 → 团队精确复现)
```

## 命令

```bash
./workspace sync            # 或 make setup / make sync
./workspace sync --locked   # 严格模式:与 lock 不一致即失败(CI/团队复现)
./workspace status          # 源 SHA、dirty、sparse、只读状态、视窗健康度
./workspace outdated        # 上游有无新 tag、lock 是否漂移
./workspace guard           # 提交防护检查(由 pre-commit 钩子调用)
./workspace clean           # 拆除 worktree 与视窗(--all 连同 git 缓存)
```

## workspace.yaml 语法

```yaml
version: 1

sources:
  <名字>:
    url: <git 地址>
    revision: <分支 | tag | SHA>        # sync 时解析为 SHA 写入 lock
    path: <工程内装配位置>               # 可嵌套(如 flow-engine/web);缺省 = 源名字
    sparse: [<目录>...]                  # 可选,cone 模式稀疏检出
    readonly: true                       # 可选,文件系统级只读(三方依赖推荐)

views:
  - source: <源名字>
    from: <源内子路径>
    to: <工作区内目标路径>               # 不得落在任何源的装配位置内
```

## 使用规则

1. **工程开发直接在装配树里进行**——全部是真实目录:IDE 打开根目录,
   `mvn` → `flow-engine/`,`pnpm` → `flow-engine/web/`。嵌套的 `web/`
   由引擎写入父仓库的 git exclude,不污染 flow-engine 的 status。
2. **视窗只看不跑**:symlink 视图里执行 pnpm/maven 会因 realpath 机制
   必然出错;docker 构建以工作区根为 context,COPY 指向 `flow-engine/...`
   等真实路径,不要把视图当 context。
3. **本地代码放根目录的真实目录**(如 `app/`、`deploy/`、`tests/`),
   外层 git 跟踪,正常编辑、提交、构建。不要放进装配目录(那是他人的
   git 工作树)或视窗(生成物,clean 即焚)。
4. **lock 入库**:提交 `workspace.lock.yaml`,团队 `git clone` +
   `./workspace sync --locked` 精确复现。升级 = 改 revision → sync →
   验证 → 配置与 lock 一并提交(显式事件,不漂移)。
5. **嵌套装配**:`path` 可位于另一源内部(如 `flow-engine/web`),引擎
   自动处理父仓库忽略;只读源内部禁止再嵌套装配。

## 只读与提交防护

- **只读锁定**:`readonly: true` 的源同步后被 chmod 锁定,编辑/新建/
  删除全部 `Permission denied`,连 `rm -rf` 都删不掉——拆除走
  `workspace clean`(自动解锁)。唯一写入者是 `workspace sync` 自身
  (同步时解锁、结束重新上锁,Nix store 思路)。三方改动请走上游 PR。
- **同步安全闸**:源有未提交改动或相对上次同步点有本地提交时,sync
  拒绝覆盖并提示处理位置。
- **提交防护**:`.githooks/pre-commit` → `workspace guard`,按
  workspace.yaml 动态计算受保护路径(全部装配目录 + 视窗),拦截
  `git add -f` 强加与嵌入式 git 仓库(gitlink)。`workspace sync`
  自动设置 `core.hooksPath`,每份克隆自动生效。装配目录对外层仓库的
  忽略同样由引擎按配置写入 `.git/info/exclude`。
- **外层仓库收录范围**:配置、lock、文档、工具、本地代码目录——
  工作区的"定义、说明与自研部分",不含任何三方源码。

## 版本管理:三层模型

| 层 | 管什么 | 谁来管 | 升级方式 |
|---|---|---|---|
| **源版本** | 每个依赖仓库取哪个快照 | `workspace.yaml` 的 revision(可读 tag)+ `workspace.lock.yaml`(精确 SHA) | 显式 bump commit |
| **产品版本** | 聚合体整体的版本号 | 外层仓库自己的 git tag | 发版 = 打 tag(tag 时刻的 lock = 完整 BOM) |
| **生态内部版本** | 各源内部 pom/package.json 的版本号 | 各自生态工具 | 随源快照 bump 自动跟随,不用手动碰 |

发版语义:外层 tag v1.0.0 时刻的 lock 钉死全部源 SHA →
`git checkout v1.0.0 && ./workspace sync --locked` 精确复现源码组合,
再 `mvn package` / `pnpm build` 即得制品。号码维护:后端用 maven
`${revision}`(CI-friendly versions),前端用 `pnpm -r` 协调 bump。

## 与 git 的关系

git 原生是单仓库工具,多仓聚合不在其职责内。本方案中所有"重活"
(mirror、worktree、sparse-checkout、rev-parse)均为 git 原生能力,
引擎(~700 行 Python)只做三件事:解析声明、循环调度、执行策略。
引擎只依赖 git 的稳定 CLI 表面;真正的资产是声明式的 yaml 与 lock——
它们平台无关,换任何语言/工具都可据此复现工程。
