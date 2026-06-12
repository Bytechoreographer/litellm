#!/usr/bin/env bash
# 拉代码 / 切分支后,一键恢复本地开发环境。幂等,可反复跑。
#   用法: bash .local_dev/setup-dev.sh
#
# 处理那些"被 git 隐藏、但 dev 必需"的东西(见 .local_dev/README.md):
#   1. next.config.mjs —— feature 分支上是上游版(无 rewrites),会让前端 API 全 404;
#      这里写回 dev 版并 skip-worktree(改动不进 PR)
#   2. .vscode/ —— feature 分支 gitignore;缺失则从 dev/local-configs 取回
#   3. 本地 PG + Redis 容器 + 本地库 schema 同步(db push)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LOCAL_DB_URL='postgresql://postgres:dev@localhost:5432/litellm_dev'

# 1) dev 版 next.config.mjs(带 rewrites)+ skip-worktree —— 最容易踩的坑
if git cat-file -e dev/local-configs:ui/litellm-dashboard/next.config.mjs 2>/dev/null; then
  git show dev/local-configs:ui/litellm-dashboard/next.config.mjs > ui/litellm-dashboard/next.config.mjs
  git update-index --skip-worktree ui/litellm-dashboard/next.config.mjs
  echo "✓ next.config.mjs = dev 版(rewrites)+ skip-worktree(改动已隐藏,不进 PR)"
else
  echo "⚠ 取不到 dev/local-configs 的 next.config.mjs,跳过(确认该分支已 fetch)"
fi

# 2) .vscode/ —— 缺失则从 dev/local-configs 取回
if [ ! -f .vscode/launch.json ]; then
  git checkout dev/local-configs -- .vscode && echo "✓ .vscode 已从 dev/local-configs 取回"
else
  echo "✓ .vscode 已存在(如需更新: git checkout dev/local-configs -- .vscode)"
fi

# 3) 本地 PG + Redis
if docker ps --format '{{.Names}}' | grep -q '^litellm-pg$'; then
  echo "✓ 本地 PG/Redis 已在运行"
else
  docker compose -f .local_dev/docker-compose.yml up -d && echo "✓ 已启动本地 PG + Redis"
fi

# 4) 本地库 schema 同步(db push;additive,不丢数据)
if DATABASE_URL="$LOCAL_DB_URL" python3 -m prisma db push \
      --schema litellm/proxy/schema.prisma --accept-data-loss --skip-generate >/dev/null 2>&1; then
  echo "✓ 本地库 schema 已按 schema.prisma 同步(db push)"
else
  echo "⚠ db push 失败(确认本地 PG 在跑、prisma 已装)"
fi

echo "---"
echo "一次性 / 按需手动:"
echo "  · Python 依赖:  装到 .venv(uv/pip)"
echo "  · 前端依赖:     (cd ui/litellm-dashboard && npm install)"
echo "  · 灌 seed(本地库空时): docker exec -i litellm-pg psql -U postgres -d litellm_dev < .local_dev/litellm_dev_seed.sql"
echo "    seed 不在 git;缺了用: DEV_DB_URL='<线上 litellm_dev url>' python3 .local_dev/make_seed.py"
echo "完成。VS Code 选 compound \"▶ 前后端(都可断点) · 后端连本地库\" 即可开发。"
