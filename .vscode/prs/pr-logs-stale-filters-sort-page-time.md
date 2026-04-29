# PR 2: fix(ui): stale filters applied after sort/page/time change on Request Logs

> **Branch**: `Bytechoreographer:fix/logs-stale-filters-on-sort-page-time`
> **Target**: `BerriAI:litellm_oss_branch`
> **PR link**: https://github.com/Bytechoreographer/litellm/pull/new/fix/logs-stale-filters-on-sort-page-time

---

## Relevant issues

<!-- No open issue found; reproduced locally. -->

## Pre-Submission checklist

- [x] `npm run test` passes for affected files (29/29)
- [x] Scope is isolated: one file changed, no new dependencies
- [ ] Comment `@greptileai` and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

🐛 Bug Fix

## Changes

### Root cause

`useLogFilterLogic` has a `useEffect` that re-fetches logs whenever sort,
page, or time range changes while backend filters are active:

```ts
useEffect(() => {
  if (hasBackendFilters && accessToken) {
    debouncedSearch.cancel();
    performSearch(filters, currentPage);   // ← stale closure!
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
}, [sortBy, sortOrder, currentPage, startTime, endTime, isCustomDate]);
```

`filters` and `hasBackendFilters` are intentionally **omitted** from the dep
array to prevent double-fetches when a filter is applied (filter changes are
handled by `handleFilterChange → debouncedSearch`).

The side-effect is a **stale-closure bug**: React captures `filters` and
`hasBackendFilters` from the render where the effect was last recreated —
i.e., when `sortBy`, `sortOrder`, `currentPage`, `startTime`, `endTime`, or
`isCustomDate` last changed.  If the user sets a filter (e.g. Key Alias)
*after* that point, the effect still holds the old snapshot that predates
the filter selection.

**Reproduce**:
1. Open Request Logs → set Key Alias filter → filtered results appear ✓  
2. Change page, sort column, or time range  
3. The effect fires with the stale `filters` (no `key_alias`) → API request
   sent without the filter → table shows **unfiltered** data ✗

This is why the filter appears to "sometimes work, sometimes not": the initial
debounce-triggered search uses the correct filters, but any subsequent
sort/page/time interaction resets the results.

### Fix

Store the latest `filters` and `hasBackendFilters` in refs kept in sync on
every render.  The sort/page/time effect reads from the refs instead of the
closure, so it always uses the **current** filter state without requiring
those values to be in the dep array:

```ts
// Always-current refs — updated every render
const filtersRef = useRef(filters);
const hasBackendFiltersRef = useRef(false);

useEffect(() => {
  filtersRef.current = filters;
  hasBackendFiltersRef.current = hasBackendFilters;
}, [filters, hasBackendFilters]);

// Sort/page/time effect now reads from refs → no stale closure
useEffect(() => {
  if (hasBackendFiltersRef.current && accessToken) {
    debouncedSearch.cancel();
    performSearch(filtersRef.current, currentPage);
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
}, [sortBy, sortOrder, currentPage, startTime, endTime, isCustomDate]);
```

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/components/view_logs/log_filter_logic.tsx` | Add `filtersRef` / `hasBackendFiltersRef`, sync effect, update sort/page/time effect to read from refs |
