-- =============================================================================
-- copy_prod_to_dev.sql  （DataGrip 兼容版）
-- 在 litellm_dev 库上执行；通过 dblink 只读访问 litellm（正式库）
--
-- DataGrip 使用方法：
--   1. 连接目标：litellm_dev
--   2. 选中全部内容 → Run（或逐段执行）
--
-- 安全保证：
--   · 所有写操作只在 litellm_dev 上执行
--   · 正式库 litellm 只通过 dblink 只读访问，不执行任何写操作
--   · ON CONFLICT DO NOTHING：已存在的行不会被修改或覆盖
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS dblink;

-- =============================================================================
-- STEP 1：预算表
-- =============================================================================
INSERT INTO "LiteLLM_BudgetTable" (
    budget_id, max_budget, soft_budget, max_parallel_requests,
    tpm_limit, rpm_limit, budget_duration, budget_reset_at,
    model_max_budget, created_at, created_by, updated_at, updated_by
)
SELECT *
FROM dblink(
    'host=963dcb2e63e249428847c22a5ca528d2in03.internal.cn-east-3.postgresql.rds.myhuaweicloud.com port=5432 dbname=litellm user=root password=''DDInfraABPP@ss#@!''',
    'SELECT budget_id, max_budget, soft_budget, max_parallel_requests,
            tpm_limit, rpm_limit, budget_duration, budget_reset_at,
            model_max_budget, created_at, created_by, updated_at, updated_by
     FROM "LiteLLM_BudgetTable"'
) AS t(
    budget_id TEXT, max_budget FLOAT8, soft_budget FLOAT8,
    max_parallel_requests INT4, tpm_limit INT8, rpm_limit INT8,
    budget_duration TEXT, budget_reset_at TIMESTAMPTZ,
    model_max_budget JSONB, created_at TIMESTAMPTZ, created_by TEXT,
    updated_at TIMESTAMPTZ, updated_by TEXT
)
ON CONFLICT (budget_id) DO NOTHING;

-- =============================================================================
-- STEP 2：组织表
-- =============================================================================
INSERT INTO "LiteLLM_OrganizationTable" (
    organization_id, organization_alias, budget_id, metadata,
    models, spend, model_spend, object_permission_id,
    created_at, created_by, updated_at, updated_by
)
SELECT *
FROM dblink(
    'host=963dcb2e63e249428847c22a5ca528d2in03.internal.cn-east-3.postgresql.rds.myhuaweicloud.com port=5432 dbname=litellm user=root password=''DDInfraABPP@ss#@!''',
    'SELECT organization_id, organization_alias, budget_id, metadata,
            models, spend, model_spend, object_permission_id,
            created_at, created_by, updated_at, updated_by
     FROM "LiteLLM_OrganizationTable"'
) AS t(
    organization_id TEXT, organization_alias TEXT, budget_id TEXT,
    metadata JSONB, models TEXT[], spend FLOAT8, model_spend JSONB,
    object_permission_id TEXT, created_at TIMESTAMPTZ, created_by TEXT,
    updated_at TIMESTAMPTZ, updated_by TEXT
)
ON CONFLICT (organization_id) DO NOTHING;

-- =============================================================================
-- STEP 3：团队表
-- =============================================================================
INSERT INTO "LiteLLM_TeamTable" (
    team_id, team_alias, organization_id, object_permission_id,
    admins, members, members_with_roles, metadata,
    max_budget, soft_budget, spend, models,
    max_parallel_requests, tpm_limit, rpm_limit,
    budget_duration, budget_reset_at, blocked,
    model_spend, model_max_budget, router_settings, team_member_permissions,
    created_at, updated_at
)
SELECT *
FROM dblink(
    'host=963dcb2e63e249428847c22a5ca528d2in03.internal.cn-east-3.postgresql.rds.myhuaweicloud.com port=5432 dbname=litellm user=root password=''DDInfraABPP@ss#@!''',
    'SELECT team_id, team_alias, organization_id, object_permission_id,
            admins, members, members_with_roles, metadata,
            max_budget, soft_budget, spend, models,
            max_parallel_requests, tpm_limit, rpm_limit,
            budget_duration, budget_reset_at, blocked,
            model_spend, model_max_budget, router_settings, team_member_permissions,
            created_at, updated_at
     FROM "LiteLLM_TeamTable"'
) AS t(
    team_id TEXT, team_alias TEXT, organization_id TEXT, object_permission_id TEXT,
    admins TEXT[], members TEXT[], members_with_roles JSONB, metadata JSONB,
    max_budget FLOAT8, soft_budget FLOAT8, spend FLOAT8, models TEXT[],
    max_parallel_requests INT4, tpm_limit INT8, rpm_limit INT8,
    budget_duration TEXT, budget_reset_at TIMESTAMPTZ, blocked BOOLEAN,
    model_spend JSONB, model_max_budget JSONB, router_settings JSONB, team_member_permissions TEXT[],
    created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
)
ON CONFLICT (team_id) DO NOTHING;

-- =============================================================================
-- STEP 4：用户表
-- =============================================================================
INSERT INTO "LiteLLM_UserTable" (
    user_id, user_alias, team_id, sso_user_id, organization_id,
    password, teams, user_role, max_budget, spend, user_email,
    models, metadata, max_parallel_requests, tpm_limit, rpm_limit,
    budget_duration, budget_reset_at, allowed_cache_controls, policies,
    model_spend, model_max_budget, created_at, updated_at
)
SELECT *
FROM dblink(
    'host=963dcb2e63e249428847c22a5ca528d2in03.internal.cn-east-3.postgresql.rds.myhuaweicloud.com port=5432 dbname=litellm user=root password=''DDInfraABPP@ss#@!''',
    'SELECT user_id, user_alias, team_id, sso_user_id, organization_id,
            password, teams, user_role, max_budget, spend, user_email,
            models, metadata, max_parallel_requests, tpm_limit, rpm_limit,
            budget_duration, budget_reset_at, allowed_cache_controls, policies,
            model_spend, model_max_budget, created_at, updated_at
     FROM "LiteLLM_UserTable"'
) AS t(
    user_id TEXT, user_alias TEXT, team_id TEXT, sso_user_id TEXT,
    organization_id TEXT, password TEXT, teams TEXT[], user_role TEXT,
    max_budget FLOAT8, spend FLOAT8, user_email TEXT, models TEXT[],
    metadata JSONB, max_parallel_requests INT4, tpm_limit INT8, rpm_limit INT8,
    budget_duration TEXT, budget_reset_at TIMESTAMPTZ,
    allowed_cache_controls TEXT[], policies TEXT[],
    model_spend JSONB, model_max_budget JSONB,
    created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
)
ON CONFLICT (user_id) DO NOTHING;

-- =============================================================================
-- STEP 5：Virtual Keys（只复制未过期的、有模型绑定的 key 及 admin key）
-- =============================================================================
INSERT INTO "LiteLLM_VerificationToken" (
    token, key_name, key_alias, soft_budget_cooldown, spend, expires,
    models, aliases, config, user_id, team_id, permissions,
    max_parallel_requests, metadata, blocked, tpm_limit, rpm_limit,
    max_budget, budget_duration, budget_reset_at, allowed_cache_controls,
    allowed_routes, policies, access_group_ids, model_spend, model_max_budget,
    budget_id, organization_id, created_at, created_by, updated_at, updated_by,
    last_active, rotation_count, auto_rotate
)
SELECT *
FROM dblink(
    'host=963dcb2e63e249428847c22a5ca528d2in03.internal.cn-east-3.postgresql.rds.myhuaweicloud.com port=5432 dbname=litellm user=root password=''DDInfraABPP@ss#@!''',
    'SELECT token, key_name, key_alias, soft_budget_cooldown, spend, expires,
            models, aliases, config, user_id, team_id, permissions,
            max_parallel_requests, metadata, blocked, tpm_limit, rpm_limit,
            max_budget, budget_duration, budget_reset_at, allowed_cache_controls,
            allowed_routes, policies, access_group_ids, model_spend, model_max_budget,
            budget_id, organization_id, created_at, created_by, updated_at, updated_by,
            last_active, rotation_count, auto_rotate
     FROM "LiteLLM_VerificationToken"
     WHERE (expires IS NULL OR expires > NOW())
       AND (
           array_length(models, 1) > 0
           OR user_id IN (
               SELECT user_id FROM "LiteLLM_UserTable"
               WHERE user_role IN (''proxy_admin'', ''proxy_admin_viewer'')
           )
       )'
) AS t(
    token TEXT, key_name TEXT, key_alias TEXT, soft_budget_cooldown BOOLEAN,
    spend FLOAT8, expires TIMESTAMPTZ, models TEXT[], aliases JSONB,
    config JSONB, user_id TEXT, team_id TEXT, permissions JSONB,
    max_parallel_requests INT4, metadata JSONB, blocked BOOLEAN,
    tpm_limit INT8, rpm_limit INT8, max_budget FLOAT8,
    budget_duration TEXT, budget_reset_at TIMESTAMPTZ,
    allowed_cache_controls TEXT[], allowed_routes TEXT[], policies TEXT[],
    access_group_ids TEXT[], model_spend JSONB, model_max_budget JSONB,
    budget_id TEXT, organization_id TEXT, created_at TIMESTAMPTZ,
    created_by TEXT, updated_at TIMESTAMPTZ, updated_by TEXT,
    last_active TIMESTAMPTZ, rotation_count INT4, auto_rotate BOOLEAN
)
ON CONFLICT (token) DO NOTHING;

-- =============================================================================
-- STEP 6：团队成员关系
-- =============================================================================
INSERT INTO "LiteLLM_TeamMembership" (user_id, team_id, spend, budget_id)
SELECT *
FROM dblink(
    'host=963dcb2e63e249428847c22a5ca528d2in03.internal.cn-east-3.postgresql.rds.myhuaweicloud.com port=5432 dbname=litellm user=root password=''DDInfraABPP@ss#@!''',
    'SELECT user_id, team_id, spend, budget_id
     FROM "LiteLLM_TeamMembership"'
) AS t(
    user_id TEXT, team_id TEXT, spend FLOAT8, budget_id TEXT
)
ON CONFLICT (user_id, team_id) DO NOTHING;

-- =============================================================================
-- 验证
-- =============================================================================
SELECT 'LiteLLM_UserTable'         AS tbl, COUNT(*) AS rows FROM "LiteLLM_UserTable"
UNION ALL
SELECT 'LiteLLM_VerificationToken',        COUNT(*) FROM "LiteLLM_VerificationToken"
UNION ALL
SELECT 'LiteLLM_TeamTable',                COUNT(*) FROM "LiteLLM_TeamTable"
UNION ALL
SELECT 'LiteLLM_OrganizationTable',        COUNT(*) FROM "LiteLLM_OrganizationTable"
UNION ALL
SELECT 'LiteLLM_BudgetTable',              COUNT(*) FROM "LiteLLM_BudgetTable";

-- 确认有 >3 个模型的 key（用于测试 expand 箭头）
SELECT token, key_alias, array_length(models, 1) AS model_count
FROM "LiteLLM_VerificationToken"
WHERE array_length(models, 1) > 3
ORDER BY model_count DESC
LIMIT 10;
