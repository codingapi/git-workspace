# Workspace Projection Layer(工作区投影层)

在 Git 与构建系统之间增加的一层:一份声明式 `workspace.yaml`,自动生成
"真实 Git 工作树 + 投影逻辑工作区"。替代 Google repo 方案——repo 的
linkfile 无法安全承载需要执行构建工具的目录(symlink 根目录与 Node 等
工具链的 realpath 解析冲突),本方案把"可执行"与"只读视图"彻底分离。

```
                 workspace.yaml
                       │
                       ▼
┌──────────────────────────────────────────────┐
│          Workspace Projection Engine         │
│        (./workspace —— 单文件 Python)         │
│   fetch / lock / sparse / worktree / link    │
└───────────────┬──────────────────────────────┘
                │
       ┌────────┴────────┐
       ▼                 ▼
 .sources/            product/
 Git 真实工作树        symlink 投影视图
(执行命令的地方)      (浏览/集成用,只读)
```

## 目录结构

```
workspace/
├── .workspace/git-cache/   bare/mirror 对象缓存(多 worktree 共享 objects)
├── .sources/               真实 Git worktree(可独立 HEAD/sparse,可构建)
│   ├── flow-engine/        full
│   ├── flow-frontend/      full         ← pnpm i / build 在这里跑
│   └── fastjson2/          sparse: core ← tag 2.0.63 钉版本
├── product/                投影出的逻辑工作区(全部是 symlink)
│   ├── flow-engine  -> ../.sources/flow-engine
│   ├── web          -> ../.sources/flow-frontend
│   ├── docs         -> ../.sources/flow-frontend/docs
│   └── third-party/fastjson2-core -> ../../.sources/fastjson2/core
├── workspace.yaml          声明式配置(入库)
└── workspace.lock.yaml     解析后的 commit SHA 快照(入库 → 团队精确复现)
```

## 命令

```bash
./workspace sync          # 或 make setup / make sync
./workspace status        # 源 SHA、dirty 状态、sparse 范围、投影健康度
./workspace clean         # 拆掉 worktree 与投影(保留缓存)
./workspace clean --all   # 连 git 缓存一起删
```

## workspace.yaml 语法

```yaml
version: 1

sources:
  <名字>:
    url: <git 地址>
    revision: <分支 | tag | SHA 表达式>   # sync 时解析为 SHA 写入 lock
    sparse: [<目录>...]                   # 可选,cone 模式(顶层文件自动保留)
    readonly: true                        # 可选,sync 后文件系统级只读(三方源推荐)

projections:
  - source: <源名字>
    from: <源内子路径,或 . 表示整仓>
    to: <工作区内目标路径>
    mode: symlink
```

## 使用规则(踩坑换来的边界认知)

1. **要执行命令 → 进 `.sources/<name>`**(真实目录,路径解析无歧义);
   `product/` 只用于浏览、IDE 导入、后端消费构建产物——不要在里面跑
   pnpm/maven 等依赖 realpath 语义的工具。
2. **构建产物自动穿透投影**:在 `.sources/flow-frontend` 里 build,
   产物 `dist/` 会即时出现在 `product/web/...` 中(symlink 按路径寻址)。
3. **lock 入库**:提交 `workspace.lock.yaml`,任何人 `git clone` 本仓库 +
   `./workspace sync` 即可复现完全相同的 commit 组合。更新版本:改
   `workspace.yaml` 的 revision → sync → 提交新 lock。
4. **sparse 注意**:Git 官方提示 sparse-checkout 行为仍可能变化,某些
   merge/rebase 或外部工具可能重新产生非 sparse 路径;`./workspace sync`
   会重新应用 sparse 集合,也可随时 `git -C .sources/<n> sparse-checkout reapply`。
5. **冲突保护**:投影目标已存在非投影内容(真实目录/文件/他人链接)时
   直接报错拒绝覆盖,绝不静默破坏用户数据。

## 只读与提交防护

**三方源文件系统级只读。** 源上配置 `readonly: true`,sync 完成后该 worktree
被 chmod 锁定:任何编辑/新建/删除直接 `Permission denied`,唯一写入者是
`workspace sync` 自身(同步时自动解锁、结束重新上锁,同 Nix store 思路)。
三方代码改动请走上游(fork → 在自己的克隆中修改 → PR),不要就地改。

**同步安全闸。** 某源工作树存在未提交改动、或与配置 revision 不一致的本地
提交时,sync 拒绝覆盖并提示处理位置——防止版本切换静默丢失工作。

**提交防护(pre-commit 钩子)。** `.githooks/pre-commit` 拦截两类误操作:

- `git add -f` 强加受保护路径(`.sources/`、`.workspace/`、`product/`)
- `git add -f .sources/<name>` 之类混入嵌入式 git 仓库(gitlink)

`workspace sync` 自动设置 `core.hooksPath=.githooks`(每份克隆自动生效)。
外层仓库的提交范围:配置、lock、文档、工具——即"工作区的定义与说明",
不含任何三方源码。本地自己的代码,直接放在工作区根目录的普通文件中,
正常编辑、正常提交。

## 为什么不用 repo / submodule

| | repo linkfile | submodule | 本方案 |
|---|---|---|---|
| 声明式布局 | ✅ | 部分 | ✅ |
| sparse 检出 | ❌ | ❌(需手工) | ✅ per-worktree |
| 同仓多 worktree/多视图 | 受限 | ❌ | ✅(git worktree 原生) |
| 版本锁定 | revision | ✅ | ✅(lock 文件) |
| 构建工具兼容 | ❌(symlink 根) | ✅ | ✅(真实工作树) |
