# PR: fix(ui): tag filter dropdown on Usage page respects selected date range

> **Branch**: `Bytechoreographer:fix/tag-list-time-window`
> **Target**: `BerriAI:litellm_internal_staging`

---

## Relevant issues

<!-- No open issue; bug reproduced locally on the Usage page with tags that have no spend in the selected period. -->

## Pre-Submission checklist

- [x] Unit tests added in `tests/test_litellm/proxy/management_endpoints/test_tag_management_endpoints.py`
- [x] `uv run pytest tests/test_litellm/proxy/management_endpoints/test_tag_management_endpoints.py -v` passes
- [x] Scope is isolated: 2 backend files + 2 frontend files, no new dependencies
- [ ] Comment `@greptileai` and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

🐛 Bug Fix / ⚡ Performance

## Changes

### Reproduction

1. Open the Usage page (`?page=new_usage`) with a date range narrow enough to exclude some tags (e.g. last 7 days).
2. Open the **Tag** filter dropdown.

**Before**: Every tag ever created in the system appears — including ones with no spend in the selected window. Users must guess which tags are relevant.

**After**: Only tags with spend within the selected date window appear. Stored (budget-configured) tags are always included regardless of the window.

---

### Root cause — tag list fetch ignores the active date filter and scans all rows

`UsagePageView.tsx` fetched all tags on mount and never re-fetched when the date range changed:

```ts
// Before — fires once on mount, never again
const getAllTags = async () => {
  const tags = await tagListCall(accessToken);
  setAllTags(...);
};
useEffect(() => {
  getAllTags();
}, [accessToken]);
```

`tagListCall` hit `/tag/list` with no query params. The backend then ran a `group_by` on `litellm_dailytagspend` with only `WHERE tag IS NOT NULL` — a **full table scan** of the entire spend history. On a busy proxy this table can contain millions of rows, making every Usage-page load unnecessarily expensive. The existing `@@index([tag, date])` composite index in `schema.prisma` is never engaged when there is no `date` predicate.

---

### Fix

Three coordinated changes:

#### 1. Backend — `GET /tag/list` accepts optional date-range params

```python
async def list_tags(
    user_api_key_dict: UserAPIKeyAuth = Depends(user_api_key_auth),
    start_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    end_date:   Optional[str] = Query(None, description="YYYY-MM-DD"),
):
```

- Validated by a pure helper `_validate_tag_list_date_range`: both must be supplied together, must parse as `%Y-%m-%d`, and `start <= end`.
- When both are present, the `group_by` WHERE clause on `litellm_dailytagspend` gains a `date` filter:

  ```python
  dynamic_tag_where: Dict[str, Any] = {"tag": {"not": None}}
  if start_date and end_date:
      dynamic_tag_where["date"] = {"gte": start_date, "lte": end_date}
  ```

  This engages the existing `@@index([tag, date])` composite index in `schema.prisma`, limiting the scan to rows within the requested window instead of the full table.

- Stored tags (`litellm_tagtable`) are always returned; date filter applies only to dynamic tags.

#### 2. Frontend — `tagListCall` forwards the date window

```ts
// networking.tsx — before
export const tagListCall = async (accessToken: string): Promise<TagListResponse>

// After
export const tagListCall = async (
  accessToken: string,
  startTime?: Date | null,
  endTime?: Date | null,
): Promise<TagListResponse>
```

When both dates are non-null, `YYYY-MM-DD` strings are appended as `?start_date=...&end_date=...`. A local `formatYmd` helper avoids locale-sensitive `toISOString()`.

#### 3. Frontend — `UsagePageView` re-fetches tags on date change

```ts
// UsagePageView.tsx — after
useEffect(() => {
  if (!accessToken) return;
  let cancelled = false;
  (async () => {
    const tags = await tagListCall(accessToken, startTime, endTime);
    if (cancelled) return;
    setAllTags(...);
  })();
  return () => { cancelled = true; };
}, [accessToken, startTime, endTime]);   // ← re-fires when date range changes
```

`startTime` and `endTime` are memoised from the existing `dateValue` state, so this effect fires only when the user actually changes the picker.

---

### Files changed

| File | Change |
|------|--------|
| `litellm/proxy/management_endpoints/tag_management_endpoints.py` | Add `start_date`/`end_date` query params + `_validate_tag_list_date_range` helper + conditional WHERE clause on `litellm_dailytagspend` |
| `tests/test_litellm/proxy/management_endpoints/test_tag_management_endpoints.py` | Add `test_list_tags_with_date_range_filters_dynamic_tags` and `test_list_tags_without_date_range_omits_date_filter` |
| `ui/litellm-dashboard/src/components/networking.tsx` | `tagListCall` gains optional `startTime`/`endTime` params; adds `formatYmd` helper |
| `ui/litellm-dashboard/src/components/UsagePage/components/UsagePageView.tsx` | Replace static mount-only tag fetch with date-aware effect that re-fetches on `[accessToken, startTime, endTime]` change |

---

### Test results

```
$ uv run pytest tests/test_litellm/proxy/management_endpoints/test_tag_management_endpoints.py -v
...
PASSED test_list_tags_with_date_range_filters_dynamic_tags
PASSED test_list_tags_without_date_range_omits_date_filter
...
```

---

### Before / After behaviour

| Scenario | Before | After |
|---|---|---|
| Tag dropdown on Usage page | Shows all tags ever seen | Shows only tags with spend in selected date window |
| No date range selected | All tags (full table scan) | All tags (full table scan, unchanged) |
| Date range selected | Full table scan regardless | `@@index([tag, date])` used — only scans the date window |
| Stored (budget-configured) tags | Always shown | Always shown (unchanged) |
| Date range changes | Dropdown unchanged | Dropdown re-fetches automatically |
| Missing only one of start/end | N/A | 400 — `"start_date and end_date must be provided together"` |
| Invalid date format | N/A | 400 — `"Invalid date format, expected YYYY-MM-DD"` |
| `start_date > end_date` | N/A | 400 — `"start_date must be on or before end_date"` |
