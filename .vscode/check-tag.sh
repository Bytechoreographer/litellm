#!/usr/bin/env bash
# 用法: check-tag.sh <pep-cd-yaml-path>
# 从 pep-cd 的 helm values 文件中动态读取 image.tag，
# 与当前 git HEAD 对比，不一致时直接中止。
# 如需强制跳过检查：在 launch.json 对应配置的 env 中加入 "SKIP_TAG_CHECK": "1"

set -euo pipefail

YAML_FILE="$1"
PEP_CD_DIR="$(cd "$(dirname "$YAML_FILE")/../.." && pwd)"  # pep-cd 根目录

# ── 1. 同步 pep-cd 到最新，确保读到的 tag 是线上真实版本 ──────────────
echo "Syncing pep-cd ..."
if git -C "$PEP_CD_DIR" pull --ff-only --quiet 2>/dev/null; then
  echo "✓  pep-cd is up to date"
else
  echo "⚠  pep-cd pull failed (offline or diverged) — using local cache"
fi

# ── 2. 从 yaml 中提取 image.tag ──────────────────────────────────────
EXPECTED=$(grep -E '^ {4}tag:' "$YAML_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$EXPECTED" ]; then
  echo "✗  Could not parse image.tag from $YAML_FILE"
  exit 1
fi

# ── 3. 获取本地 HEAD 的 tag 信息 ─────────────────────────────────────
HEAD_TAGS=$(git tag --points-at HEAD 2>/dev/null | tr '\n' ' ' | xargs)
HEAD_DESC=$(git describe --tags --always 2>/dev/null)

# ── 4. 对比 ───────────────────────────────────────────────────────────
echo ""
if echo "$HEAD_TAGS" | grep -qwF "$EXPECTED"; then
  echo "✓  Tag aligned: $EXPECTED"
  echo ""
  exit 0
fi

echo "✗  Tag mismatch — local HEAD is NOT at the deployed version"
echo "   Expected : $EXPECTED  (from $(basename "$YAML_FILE"))"
echo "   HEAD tags: ${HEAD_TAGS:-<none>}"
echo "   git desc : $HEAD_DESC"
echo ""
echo "   To align:"
echo "     git fetch --tags"
echo "     git checkout $EXPECTED"
echo ""
echo "   To launch anyway (not recommended):"
echo "     Add \"SKIP_TAG_CHECK\": \"1\" to this config's env in launch.json"
echo ""

if [ "${SKIP_TAG_CHECK:-0}" = "1" ]; then
  echo "⚠  SKIP_TAG_CHECK=1 detected — proceeding despite mismatch"
  echo ""
  exit 0
fi

exit 1
