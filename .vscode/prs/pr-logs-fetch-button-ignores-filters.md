# PR 1: fix(ui): Fetch button ignores active filters on Request Logs page

> **Branch**: `Bytechoreographer:fix/logs-fetch-button-ignores-active-filters`
> **Target**: `BerriAI:litellm_oss_branch`
> **PR link**: https://github.com/Bytechoreographer/litellm/pull/new/fix/logs-fetch-button-ignores-active-filters

---

## Relevant issues

<!-- No open issue found; reproduced locally. -->

## Pre-Submission checklist

- [x] `npm run test` passes for affected files (29/29)
- [x] Scope is isolated: two files changed, no new dependencies
- [ ] Comment `@greptileai` and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

🐛 Bug Fix

## Changes

### Root cause

The manual **Fetch** button on the Request Logs page calls `logs.refetch()`,
which re-runs the main TanStack Query.  That query's `params` object does not
include backend-only filter values such as `key_alias`:

```ts
// index.tsx – main query params (simplified)
params: {
  api_key: selectedKeyHash || undefined,
  team_id: selectedTeamId || undefined,
  status_filter: selectedStatus || undefined,
  model_id: selectedModelId || undefined,
  // ← key_alias is never set here
}
```

When a backend filter like **Key Alias** is active, `hasBackendFilters` is
`true` and `isMainQueryEnabled` is set to `false` — the main query is
intentionally disabled.  However, TanStack Query's `refetch()` bypasses the
`enabled` flag, so clicking Fetch still fires the main query.  Two problems
result:

1. A redundant API request is sent **without** the active filter params.
2. The filtered result set (`backendFilteredLogs`) is **never refreshed** —
   it stays frozen at the last debounce-triggered fetch.  The button appears
   to do nothing from the user's perspective.

### Fix

Expose a `refetchWithFilters(page?)` method from `useLogFilterLogic` that
calls `performSearch` with the current filter state.  Route the Fetch button
through it when `hasBackendFilters` is true:

```ts
// log_filter_logic.tsx – new export
const refetchWithFilters = useCallback(
  (page = currentPage) => {
    if (hasBackendFilters && accessToken) {
      debouncedSearch.cancel();
      performSearch(filters, page);
    }
  },
  [hasBackendFilters, accessToken, filters, currentPage, performSearch, debouncedSearch],
);
```

```ts
// index.tsx – updated handleRefresh
const handleRefresh = () => {
  if (hasBackendFilters) {
    refetchWithFilters();   // ← filter-aware refresh
  } else {
    logs.refetch();         // ← original path for unfiltered view
  }
};
```

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/components/view_logs/log_filter_logic.tsx` | Add `refetchWithFilters`, expose in return value |
| `ui/litellm-dashboard/src/components/view_logs/index.tsx` | Destructure `refetchWithFilters`, update `handleRefresh` |
