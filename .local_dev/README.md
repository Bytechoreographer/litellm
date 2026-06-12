# 本地开发栈（Postgres + Redis）

完全脱离共享 `litellm_dev` 库,在本地起一套 PG + Redis,schema 用 `prisma db push` 按当前分支的
`schema.prisma` 同步,再灌入从线上 dev 库导出的实体数据。

> **为什么用 `db push` 而不是 migrate?** 后端启动自带的 `prisma migrate deploy`(litellm-proxy-extras)
> 落后于当前 worktree 的 `schema.prisma`,会漏掉最近的列(如 `search_tools` / `blocked` / `env_vars`),
> 导致运行时 "column does not exist"。`db push` 直接对齐 `schema.prisma`,列才齐全;因此后端启动用
> `DISABLE_SCHEMA_UPDATE=true` 跳过那套落后的 migrate。这就是 Prisma 官方"dev 用 db push、prod 用 migrate"的做法。

> ⚠️ `litellm_dev_seed.sql` 含真实哈希 key / 加密 BYOK 凭据 / 用户邮箱,**已在 git 排除,切勿提交、外发**。
> 它不进仓库;换机器用 `make_seed.py` 重新导出即可。

## 需要的组件

| 组件 | 说明 |
|------|------|
| Postgres 15 | DB 模式必需(compose 已含,匹配 dev 服务端 15.10) |
| Redis 7 | 此 dev config 用到:router `usage-based-routing-v2`、redis 缓存、transaction buffer(compose 已含) |
| Python + litellm 依赖 | 已有(后端就是它跑的) |
| prisma CLI + query engine | 已有(db push / 建 client 用) |
| Node + npm | 已有(前端 dashboard) |
| LLM provider 网络 | 仅当要真实跑 completion 时;config 里的 vLLM `10.251.18.138` 需内网。纯管理面 / UI 开发不需要 |

镜像走公司 artifactory 镜像源(compose 里已是 `artifactory.momenta.works/docker/...`)。

## 首次搭建

```bash
# 1. 起本地 PG + Redis
docker compose -f .local_dev/docker-compose.yml up -d

# 2. 按 schema.prisma 同步本地库(列才齐全)
DATABASE_URL='postgresql://postgres:dev@localhost:5432/litellm_dev' \
  python3 -m prisma db push --schema litellm/proxy/schema.prisma

# 3. 灌入实体数据(data-only,session_replication_role=replica 已处理外键顺序)
docker exec -i litellm-pg psql -U postgres -d litellm_dev < .local_dev/litellm_dev_seed.sql
```

然后在 VS Code 的 Run and Debug 里选 compound **"▶ 前后端(都可断点) · 后端连本地库"** 启动即可
——它同时起〔后端 debug(连本地库,可断点)〕+〔前端〕,后端配置已内置本地 `DATABASE_URL` +
`DISABLE_SCHEMA_UPDATE=true`,无需手改 env。

## 日常

- 平时直接选上面那个 compound("▶ 前后端(都可断点) · 后端连本地库")开发(后端可断点)。
- **切到 schema 有新列的分支后**:`Terminal → Run Task → "local DB: db push (sync schema)"` 跑一次补列,再启动。
- 想清空重来:`docker compose -f .local_dev/docker-compose.yml down -v`(`-v` 删数据卷)→ 重新走"首次搭建"。
- 不加 `-v` 的 `down` / 重启容器 / 重启机器 → 数据都在(具名卷 `local_dev_litellm_pg_data` 持久化)。

## seed 内容(从线上 dev 库导出,2026-06 时点)

| 表 | 行数 |
|----|------|
| LiteLLM_Config | 4 |
| LiteLLM_CredentialsTable | 32 |
| LiteLLM_ObjectPermissionTable | 10 |
| LiteLLM_ProxyModelTable | 112 |
| LiteLLM_TeamTable | 17 |
| LiteLLM_UserTable | 2501 |
| LiteLLM_VerificationToken | 2632 |

已排除的重型分析表(本地开发用不到,共 ~1.6GB):`DailyTagSpend` / `SpendLogs` /
`DailyTeamSpend` / `DailyEndUserSpend` / `DailyUserSpend` / `EndUserTable` / `SpendLogToolIndex`。
重新导出:`DEV_DB_URL='<litellm_dev url>' python3 .local_dev/make_seed.py`
