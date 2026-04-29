# PR: fix(ui): team members tab — O(1) lookup + client-side pagination & search

> **Branch**: `Bytechoreographer:fix/team-members-tab-slow-render`
> **Target**: `Bytechoreographer:mmt-patch/v1.70.4-nightly`

---

## Relevant issues

<!-- No open issue; reproduced locally with a team of several hundred members. -->

## Pre-Submission checklist

- [x] Extended tests in `ui/litellm-dashboard/src/components/team/TeamMemberTab.test.tsx`
- [x] `npm run test` passes for affected files
- [x] Scope is isolated: two source files changed, one test file updated
- [ ] Comment `@greptileai` and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

⚡ Performance / 🐛 Bug Fix

## Changes

### Root cause 1 — O(n²) membership lookups on every render

Every extra column (Current Cycle Spend, Total Spend, Budget, Rate Limits,
Allowed Models, Budget Reset) called `Array.find()` over `team_memberships`
for each row, on every render:

```ts
// Before — called once per cell, per row, per render
const membership = teamData.team_memberships.find((tm) => tm.user_id === userId);
```

With 2 000 members × 6 columns = **12 000 linear scans per render**.
React re-renders `TeamMemberTab` on every state change (modal open, hover,
parent re-render), so the cost compounds rapidly and freezes the browser tab.

### Root cause 2 — entire member list rendered into the DOM at once

All members were rendered as table rows with no pagination. With thousands
of rows, each containing Tags and Tooltips, the initial paint and every
subsequent diff take noticeably long.

### Fix 1 — `useMemo` Map for O(1) lookups

```ts
// After — built once when team_memberships changes
const membershipsMap = useMemo(
  () => new Map(
    teamData.team_memberships
      .filter(tm => tm.user_id)
      .map(tm => [tm.user_id, tm])
  ),
  [teamData.team_memberships],
);

// Every column: one hash lookup instead of a full scan
const membership = membershipsMap.get(userId);
```

For 2 000 members the per-render cost drops from ~12 000 iterations to
~12 Map lookups.

### Fix 2 — client-side pagination via antd `Pagination`

- Default **50 rows/page** — a fixed-size DOM slice regardless of total member count
- Page size selector: 10 / 25 / 50 / 100
- Quick-jumper input to go directly to any page
- Pagination control rendered in the top-right header row (consistent with
  other tables in the codebase)

### Fix 3 — search + role filter

- Real-time search by email or user ID (client-side, no extra API call)
- Role dropdown filter (Admin / User)
- Changing search/filter resets to page 1 via React `key` prop on `MemberTable`,
  cleanly resetting internal pagination state without prop drilling

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/components/common_components/MemberTable.tsx` | Add `withPagination` / `defaultPageSize` props; render antd `Pagination` top-right when enabled; client-side row slicing. Backward-compatible — callers without `withPagination` are unaffected. |
| `ui/litellm-dashboard/src/components/team/TeamMemberTab.tsx` | Replace all `Array.find()` with `membershipsMap.get()`; add search + role filter UI; pass `withPagination` to `MemberTable` |
| `ui/litellm-dashboard/src/components/team/TeamMemberTab.test.tsx` | Extend coverage: filter by role, search by email/user_id, pagination slice, edit modal receives correct membership data |

### Performance summary

| Scenario | Before | After |
|---|---|---|
| Membership lookup cost per render | O(members × columns) | O(columns) |
| DOM rows painted on tab open | All members | ≤ 50 (one page) |
| Interaction lag (scroll, modal open) | Freezes at scale | Smooth |
