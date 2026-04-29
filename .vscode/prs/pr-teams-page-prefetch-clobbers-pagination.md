# PR: fix(ui): stop page.tsx prefetch from overwriting teams table pagination

> **Branch**: `Bytechoreographer:fix/teams-table-pagination`
> **Target**: `BerriAI:litellm_internal_staging`

---

## Relevant issues

<!-- No open issue; bug reproduced locally on `?page=teams` with more than 10 teams in the proxy DB. -->

## Pre-Submission checklist

- [x] Updated tests in `ui/litellm-dashboard/src/components/OldTeams.test.tsx` (30/30 pass)
- [x] `npx vitest run src/components/OldTeams.test.tsx` passes for affected file
- [x] Scope is isolated: two source files changed, one test file updated
- [ ] Comment `@greptileai` and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

🐛 Bug Fix

## Changes

### Reproduction

Open `http://localhost:3000/?page=teams` with more than 10 teams in the
proxy DB. The page shows the correct 10-per-page table briefly, then
visibly flashes to a list of up to 100 teams — defeating the pagination
control in the top-right.

Network tab shows two requests, in this order:

```
GET /v2/team/list?page=1&page_size=10&sort_by=created_at&sort_order=desc
GET /v2/team/list?page=1&page_size=100
```

### Root cause — two effects fighting over the same `teams` state

Two independent `useEffect`s write to the same top-level `teams` state
declared in `src/app/page.tsx`:

1. **`OldTeams.tsx`** owns the teams page and its server-side
   pagination. On mount it calls `fetchTeamsV2()` with
   `page_size=10, sort_by=created_at, sort_order=desc` and calls
   `setTeams(response.teams)` — where `setTeams` is inherited via props
   from the top-level state in `page.tsx`.

2. **`src/app/page.tsx`** has a separate effect that runs when
   `accessToken`, `userID`, and `userRole` all become truthy:

   ```ts
   useEffect(() => {
     ...
     if (accessToken && userID && userRole) {
       v2TeamListCall(accessToken, 1, 100, {...})
         .then(response => setTeams(response.teams ?? []))
     }
     ...
   }, [accessToken, userID, userRole]);
   ```

   This writes up to 100 teams into the **same** top-level state.

Because JWT decoding is async, the three deps resolve in separate
renders, so this effect typically fires a moment **after** `OldTeams`
has already populated the state with its paginated 10 rows. The 100-row
response then clobbers the paginated view — exactly the flash users see.

The prefetch in `page.tsx` is not specific to the teams page: it also
seeds team dropdowns on other pages (api-keys, models, users, agents,
new_usage). But it has no business driving the state that backs the
paginated teams table.

### Fix — move teams state into `OldTeams`

Make `OldTeams` own its own `teams` list locally. The parent no longer
passes `teams` / `setTeams` into it, so the parent's prefetch can't
stomp on the paginated view.

```tsx
// Before — OldTeams.tsx
interface TeamProps {
  teams: Team[] | null;
  setTeams: React.Dispatch<React.SetStateAction<Team[] | null>>;
  // ...
}

// After
interface TeamProps {
  // teams / setTeams removed
}

const Teams: React.FC<TeamProps> = ({ ... }) => {
  const [teams, setTeams] = useState<Team[] | null>(null);
  // ...
};
```

```tsx
// Before — src/app/page.tsx
<OldTeams
  teams={teams}
  setTeams={setTeams}
  accessToken={accessToken}
  // ...
/>

// After
<OldTeams
  accessToken={accessToken}
  // ...
/>
```

The top-level `[teams, setTeams]` in `page.tsx` and its `v2TeamListCall`
prefetch are kept unchanged — other pages that still read the top-level
`teams` (UserDashboard, OldModelDashboard, ViewUserDashboard,
AgentsPanel, NewUsagePage) continue to work.

### Why not just remove the `page.tsx` prefetch?

That would also work for this specific symptom, but the top-level
`teams` is consumed by five other panels as seed data for dropdowns
and selectors. Deleting the prefetch would leave those panels empty
on first paint. Isolating the teams-page state from the shared state
fixes the bug without affecting any other consumer.

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/components/OldTeams.tsx` | Drop `teams` / `setTeams` from `TeamProps`; add local `useState<Team[] \| null>`. The three existing `setTeams(...)` call sites now write to local state with no change to their bodies. |
| `ui/litellm-dashboard/src/app/page.tsx` | Stop passing `teams` / `setTeams` into `<OldTeams>`. Top-level `teams` state and the `v2TeamListCall(accessToken, 1, 100, ...)` prefetch are preserved for other consumers. |
| `ui/litellm-dashboard/src/components/OldTeams.test.tsx` | Import `teamListCall` from `@/app/(dashboard)/hooks/teams/useTeams`; add `mockTeamsResponse(teams)` helper that queues `v2TeamListCall` to return the given list; remove the `teams={...}` / `setTeams={vi.fn()}` props from all 15 render sites; tests that need a populated table now call `mockTeamsResponse([...])` before rendering. |

### Test results

```
$ npx vitest run src/components/OldTeams.test.tsx
 ✓ src/components/OldTeams.test.tsx (30 tests) 41499ms
 Test Files  1 passed (1)
      Tests  30 passed (30)
```

### Before / After behavior

| Scenario | Before | After |
|---|---|---|
| Landing on `?page=teams` with >10 teams | Shows 10 rows, flashes to up to 100 | Shows 10 rows, stays at 10 |
| Paginating, sorting, filtering | Occasionally reset by parent prefetch | Controlled entirely by OldTeams |
| Other pages that consume top-level `teams` (api-keys, models, users, agents, new_usage) | Works | Unchanged |
