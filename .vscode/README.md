# .vscode 本地调试配置说明

本目录包含 Momenta 内部专用的本地调试配置，不合入 BerriAI 上游，统一维护在
`bytechoreographer/dev/local-configs` 和 `origin/dev/local-configs` 分支。

---

## 文件说明

### launch.json

VS Code 调试启动配置，包含以下入口：

单个配置(`configurations`):

| 名称 | 说明 |
|------|------|
| **后端(debug,可断点) · 连线上 dev 库 litellm_dev** | 仅起后端(debugpy，可断点)，连线上 `litellm_dev`。preLaunchTask `check-tag: Dev` 校验代码版本与 dev 部署一致。 |
| **后端(debug,可断点) · 连本地库 localhost(PG+Redis)** | 仅起后端(debugpy，可断点)，连本地 PG+Redis；带 `DISABLE_SCHEMA_UPDATE=true` 跳过迁移(schema 由 db push 管)。⚠️ 需先 `docker compose ... up -d` 且已 db push。 |
| **前端 · next dev (rewrites, 连本地:4000)** | 仅起 next dev(rewrites 模式)，前端走相对 URL 连本地 :4000。可单独跑(需另起后端)，也被下方 compound 引用。 |
| ~~后端(debug) · 连线上【生产】库 litellm~~ | 连 `litellm` 生产库,⚠️ 写生产。**已注释停用**(危险，先保留勿删)。 |
| ~~Frontend: Dashboard (K8s Dev / Prod)~~ | 连线上 K8s 集群的 port-forward 配置，**已注释停用**(太不稳定，先保留勿删)。 |

复合配置(`compounds`，前后端一起、**两个都是真调试进程**):

| 名称 | 说明 |
|------|------|
| **▶ 前后端(都可断点) · 后端连线上 dev 库** | 同时起〔后端 debug · 线上 dev 库〕+〔前端〕。后端能断点,前端热更新。 |
| **▶ 前后端(都可断点) · 后端连本地库** | 同时起〔后端 debug · 本地库〕+〔前端〕。⚠️ 需先 `docker compose -f .local_dev/docker-compose.yml up -d`。 |

环境变量（DATABASE_URL、API Keys、Redis 密码等）全部在 `launch.json` 的 `env` 块中注入，
不写入 `proxy_config.*.yaml`。

#### 跳过 tag 检查

如需强制启动（如临时调试未发布代码），在对应配置的 `env` 中取消注释：
```json
"SKIP_TAG_CHECK": "1"
```

---

### tasks.json

VS Code task 定义，被 `launch.json` 的 `preLaunchTask` 自动触发，也可手动运行（`Terminal → Run Task`）。

| Task 标签 | 说明 |
|-----------|------|
| **prisma: generate** | 根据 `litellm/proxy/schema.prisma` 生成 Prisma Client，schema 变更后首次启动自动触发。 |
| **check-tag: Dev** | 调用 `check-tag.sh`，从 `pep-cd/llm-api-gateway/dev.yaml` 读取部署镜像 tag，与本地 HEAD 对比；不一致时中止启动。自动 `git pull pep-cd` 获取最新版本号。供 "后端 Dev (debug)" 配置。 |
| ~~check-tag: Prod~~ | 同上读 `prod.yaml`，**已注释停用**（配套的 Backend Prod 配置已注释）。 |
| ~~ui: build~~ | `npm run build` 并 `cp` 产物到 `litellm/proxy/_experimental/out/`（把 UI 打进后端静态）。**已注释停用**（当前走 `npm run dev` 热更新，没配置引用它）。 |
| ~~backend: online dev DB / local DB (port 4000)~~ | 旧的 shell 方式起后端,**已注释停用**——改用 launch.json 的 debugpy 后端配置 + compound(后端可断点),不再需要 shell task。 |
| **local DB: db push (sync schema)** | 按 `schema.prisma` 同步本地库,补齐后端自带 migrate 漏掉的新列(切到含新列的分支后手动 Run Task 一次)。详见 `.local_dev/README.md`。 |
| ~~port-forward: K8s Dev / Prod~~ | `kubectl port-forward` 到线上 dev/prod 集群,**已在 tasks.json 注释停用**(太不稳定,先保留勿删)。 |

---

### check-tag.sh

```
用法: check-tag.sh <pep-cd-yaml-path>
```

1. `git pull --ff-only pep-cd` 同步最新部署配置
2. 从 YAML 中解析 `image.tag`
3. 与 `git tag --points-at HEAD` 对比
4. 不一致则打印提示并 `exit 1`（中止 VS Code 启动）；设置 `SKIP_TAG_CHECK=1` 可跳过

依赖：`pep-cd` 仓库需克隆在 `../pep-cd/`（与本仓库同级目录）。

---

### proxy_config.dev.yaml

本地后端启动配置，对应 `pep-cd/llm-api-gateway/dev.yaml` 的 configMap。

- 数据库：`litellm_dev`
- 额外 model：`Qwen3-235B-A22B`（内网 vLLM，`10.251.18.138:30290`）
- 敏感信息全部通过 `launch.json` 的 `env` 注入

---

### proxy_config.prod.yaml

本地后端启动配置，对应 `pep-cd/llm-api-gateway/prod.yaml` 的 configMap。

- 数据库：`litellm`（生产库）
- ⚠️ 生产配置，本地启动时实际读写生产数据库
- 敏感信息通过 `launch.json` 的 `env` 注入

---

### copy_prod_to_dev.sql

DataGrip 兼容的 SQL 脚本，通过 `dblink` 扩展将生产库数据只读镜像到 `litellm_dev`：

复制顺序（外键依赖顺序）：
1. `LiteLLM_BudgetTable`
2. `LiteLLM_OrganizationTable`
3. `LiteLLM_TeamTable`
4. `LiteLLM_UserTable`
5. `LiteLLM_VerificationToken`（仅复制未过期的、有模型绑定的 key 及 admin key）
6. `LiteLLM_TeamMembership`

所有写操作只在 `litellm_dev` 执行，生产库只读。`ON CONFLICT DO NOTHING` 保证幂等。

**使用方法（DataGrip）：**
1. 连接目标数据库：`litellm_dev`
2. 打开此文件，全选 → Run

---

### prs/

PR 描述草稿，每个文件对应一个 PR，命名规则 `pr-<feature-slug>.md`。

---

## ui/litellm-dashboard/next.config.mjs

相对于上游版本，本地版本增加了以下 dev-only 能力：

```
isDev = process.env.NODE_ENV === "development"
```

| 修改点 | 说明 |
|--------|------|
| `output: "export"` → 条件式 | dev 模式下禁用 static export，保留 HMR 和 rewrites |
| `assetPrefix` → 条件式 | dev 模式下置空，prod 模式下保持 `/litellm-asset-prefix` |
| `redirects()` | `/ui/:path*` → `/:path*`，消除 prod 特有的 `/ui/` 前缀 |
| `rewrites()` | 所有非 Next.js 请求代理到 `LITELLM_BACKEND_URL`（默认 `localhost:4000`）；配合 `NEXT_PUBLIC_USE_REWRITES=true` 使前端用相对 URL，避免跨端口 redirect 导致 chunk 404 |

此文件在主分支通过 `git update-index --skip-worktree` 隐藏，不会被 `git status` 显示为修改。
切换到 `dev/local-configs` 分支后直接 committed。

---

## 前置依赖

| 依赖 | 说明 |
|------|------|
| `pep-cd` 仓库 | 与本仓库同级克隆，路径 `../pep-cd/` |
| `kubectl` | 配置了 `web-dev-a`（dev）和 `web-a`（prod）context |
| `prisma` CLI | `npm install -g prisma` 或通过 `devDependencies` 安装 |
| 内网代理 | `10.34.6.157:3128`，访问 K8s 集群、Redis、华为云 PG 时需要 |
