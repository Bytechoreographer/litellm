# PR: fix(ui): prevent infinite re-render loop in VirtualKeysTable

## Relevant issues

<!-- No open issue found; bug reproduced locally in dev mode. -->

## Pre-Submission checklist

- [x] Added tests in `ui/litellm-dashboard/src/components/key_team_helpers/filter_logic.test.tsx`
- [x] `npm run test` passes for affected files (34/34)
- [x] Scope is isolated: one source file changed, one test file updated
- [ ] Comment `@greptileai` on the PR and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

🐛 Bug Fix

## Changes

### Root cause

`VirtualKeysTable.tsx` passed `keys?.keys || []` directly into `useFilterLogic`:

```tsx
useFilterLogic({
  keys: keys?.keys || [],   // ← new [] literal on every render
  ...
})
```

While `keys` is loading (`keys?.keys` is `undefined`), the `|| []` fallback
produces a **new array reference on every render**.  The `useEffect([keys, filters])`
inside `useFilterLogic` treats each new reference as a change, calls
`setFilteredKeys`, which triggers a re-render, which produces another new `[]`…
resulting in an infinite loop.

In development mode this surfaces as:

```
Maximum update depth exceeded.
src/components/key_team_helpers/filter_logic.tsx (102:5) @ useFilterLogic.useEffect
```

In the production build React's production runtime silences the warning, but
the excess re-renders still occur on every page load.

### Fix

Stabilise the reference with `useMemo` before passing it to the hook
(`VirtualKeysTable.tsx`):

```tsx
// Before
useFilterLogic({
  keys: keys?.keys || [],
  ...
})

// After
const keysList = useMemo(() => keys?.keys ?? [], [keys?.keys]);

useFilterLogic({
  keys: keysList,
  ...
})
```

`useMemo` returns the **same** `[]` across renders until `keys?.keys` actually
changes, breaking the loop.  `??` is used instead of `||` to correctly handle
`null` as well as `undefined`.

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/components/VirtualKeysPage/VirtualKeysTable.tsx` | Add `useMemo` to stabilise `keys` reference |
| `ui/litellm-dashboard/src/components/key_team_helpers/filter_logic.test.tsx` | Add 2 regression tests |

### Tests added (`filter_logic.test.tsx`)

| Test | What it verifies |
|------|-----------------|
| `should not enter an infinite render loop when keys prop is re-rendered with a new empty-array reference` | Simulates the `\|\| []` pattern: calls `rerender({ keys: [] })` three times; the hook must complete without hanging |
| `should update filteredKeys when keys prop changes from empty to populated` | Verifies `filteredKeys` correctly reflects new data when `keys` transitions from `[]` to a populated array |
