# git-workspace

[English](README.md) | **中文**

git-workspace 是一个 git 多仓库工作区管理工具。在一份 YAML 里声明所有仓库,
一条命令即可把它们装配成一棵真实的工程目录树 —— 全部由真实的 git worktree
构成,没有任何 symlink。用 IDE 打开根目录,照常开发、构建、调试。

## 特性

- 📄 **一份声明式配置** —— `git-workspace.yaml` 描述每个仓库:地址、版本、装配位置
- 🌲 **真实目录树** —— 由 git worktree 装配而成,IDE、pnpm、maven、docker 看到的都是真实路径
- 🔍 **稀疏检出** —— `include`/`exclude` 过滤器,只取需要的内容
- 🔒 **只读依赖** —— 三方代码在文件系统级锁定,唯一写入者只有 `sync`
- 📌 **可复现** —— lock 文件钉死精确 commit SHA,`sync --locked` 精确复现(适合 CI)
- 🛡 **提交防护** —— pre-commit 钩子防止三方代码误提交进你的仓库
- 🚀 **自我更新** —— `git-workspace update` 一键升级到最新发布版本

## 如何使用

### 安装

依赖:Python 3.8+、git、PyYAML(安装脚本会自动检查并安装 PyYAML)。
独立安装始终钉住**最新的发布 tag**,而不是开发分支。

**Linux / macOS / Git Bash:**

```bash
curl -fsSL https://raw.githubusercontent.com/codingapi/git-workspace/main/install.sh | sh
```

**Windows(PowerShell):**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/codingapi/git-workspace/main/install.ps1) }"
```

从克隆安装:`./install.sh`(`--prefix DIR` 可覆盖默认的 `~/.local`)。

### 建立工作区

```bash
mkdir my-project && cd my-project && git init
git-workspace init          # 创建 git-workspace.yaml + 提交防护钩子
# 编辑 git-workspace.yaml,声明你的仓库
git-workspace sync          # 拉取全部源,装配出工程树
```

一份最小配置:

```yaml
version: 1
sources:
  my-backend:
    url: git@github.com:example/my-backend.git
    revision: main
    path: my-backend                 # 装配位置(可嵌套,如 my-backend/web)
  my-lib:
    url: git@github.com:example/my-lib.git
    revision: v1.0.0
    path: libs/my-lib
    include: [core]                  # 只检出 core/
    readonly: true                   # 文件系统级只读锁定
```

之后直接在装配好的目录树里开发。任何你没有声明的目录(如
`app/`)都会被外层 git 仓库照常跟踪 —— 不需要手工配置任何 `.gitignore`。

本仓库自带一个可运行的示例:`cp example.yaml git-workspace.yaml &&
git-workspace sync`,会装配一个后端仓库、一个嵌套的前端仓库,以及同一个三方库
的两份过滤后只读检出。

## 如何卸载

**Linux / macOS / Git Bash:**

```bash
curl -fsSL https://raw.githubusercontent.com/codingapi/git-workspace/main/install.sh | sh -s -- --uninstall
```

**Windows(PowerShell):**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/codingapi/git-workspace/main/install.ps1) } -Uninstall"
```

从克隆安装的?重新执行 `./install.sh --uninstall`。
如需同时清掉某个工作区的 worktree 与缓存:先执行 `git-workspace clean --all`。

## 常用指令

| 指令 | 说明 |
|---|---|
| `git-workspace init` | 在当前目录创建初始配置 + 提交防护钩子 |
| `git-workspace sync` | 拉取全部源、物化 worktree、刷新 lock |
| `git-workspace sync --locked` | 精确检出 lock 中的 SHA;要求配置与 lock 一致;不重写 lock(CI) |
| `git-workspace status` | 查看各源 SHA、dirty 状态、检出过滤、只读状态 |
| `git-workspace outdated` | 检查 lock 漂移与上游新 tag |
| `git-workspace verify` | CI 完整性校验:各源与 lock 一致、只读源干净且已锁定(失败时非零退出) |
| `git-workspace update` | 自我更新到最新发布版本 |
| `git-workspace clean [--all]` | 拆除 worktree(`--all` 连同对象缓存一起清除) |
| `git-workspace version` | 打印版本(也支持 `-V` / `--version`) |

`git-workspace guard` 由 pre-commit 钩子调用,一般不用手动执行。
`Makefile` 包装了常用指令(`make sync`、`make status`、`make install` 等)。

## 核心组件与工作原理

```
git-workspace.yaml ──▶ 引擎 ──▶ .workspace/git-cache/      (镜像克隆,按 URL 共享)
                         │               │
                         ▼               ▼
            git-workspace.lock.yaml   各装配位置上的真实 worktree
                         +       托管 git 过滤块 & pre-commit 钩子
```

- **引擎** —— `git-workspace` 本体:单文件 Python CLI(约 850 行),只依赖
  git 与 PyYAML。它解析配置、编排顺序,所有重活(mirror clone、worktree、
  sparse-checkout、版本解析)全部委托给 git 原生能力。
- **两种仓库角色** —— 开发型仓库全量检出、可编辑,构成你的工程本体;
  消费型依赖配检出过滤 + 文件系统级只读锁,唯一写入者是本工具——
  `sync` 会拒绝在已被改动的只读源上运行,`verify` 也会标记它。
  该锁是防误操作的护栏(POSIX 权限位;Windows 上为只读文件属性),
  并非安全边界——CI 若要防篡改,请改用只读挂载与只读凭证。
- **镜像缓存** —— `.workspace/git-cache/` 下的 bare 克隆,按 URL 键控;
  同一仓库的多个源共享同一个对象库,绝不重复下载。
- **lock 文件** —— `sync` 将每个 revision 解析为 SHA 并写入
  `git-workspace.lock.yaml`。提交入库后,任何人(或 CI)用
  `sync --locked` 精确复现整棵树:该模式直接检出 *lock 中的* SHA
  (忽略 `main` 这类浮动 revision 的上游推进),要求配置的 source 集合、
  `url`、`revision` 与 lock 一致,且绝不重写 lock。随后 `verify`
  可断言已物化的树与 lock 一致、只读源干净且已锁定。
- **工作区根发现** —— CLI 从当前目录逐级向上查找 `git-workspace.yaml`,
  因此无论是全局安装还是从克隆直接运行,行为完全一致。
- **托管 git 过滤** —— 每次 sync 整体重写各仓库 exclude 文件中的标记块
  (自我修复):装配路径被外层仓库忽略,未声明的内容照常跟踪。
- **安全性** —— 有未提交改动或本地提交时,sync 拒绝覆盖;`guard` 钩子
  拦截强加装配目录或嵌入式 git 仓库进外层仓库的提交。
- **发布通道** —— 安装脚本钉住最新发布 tag,`git-workspace update`
  与本地版本对比后就地升级。

## 如何贡献代码

开发只需 Python 3、PyYAML 和 git —— 直接从克隆运行 CLI:

```bash
git clone git@github.com:codingapi/git-workspace.git && cd git-workspace
./git-workspace -h
# 用自带示例做端到端冒烟测试:
cp example.yaml git-workspace.yaml && ./git-workspace sync && ./git-workspace status
./git-workspace clean --all && rm git-workspace.yaml git-workspace.lock.yaml
```

约定:

- 保持单文件设计 —— 整个引擎就是 `git-workspace`,无构建步骤,只用标准库 + PyYAML。
- 保持声明式 —— 新能力应体现在 `git-workspace.yaml` 里,而不是堆命令行参数。
- 暂无测试套件 —— 改动后用上面的冒烟测试和 `git-workspace -h` 验证。
- 发版流程:升级 `__version__` → 提交 → `git tag v<version>` → 推送 tag,安装脚本与 `update` 会自动感知。

Issue 与 Pull Request:https://github.com/codingapi/git-workspace
