# PR: fix(ui): wrap selected models in the multi-select picker instead of collapsing onto one row

> **Branch**: `Bytechoreographer:litellm_team_model_select_wrap`
> **Target**: `BerriAI:litellm_internal_staging`
> **PR link**: https://github.com/Bytechoreographer/litellm/pull/new/litellm_team_model_select_wrap

---

## Relevant issues

<!-- No upstream issue; reported internally on the Teams page edit form -->

## Pre-Submission checklist

- [x] `npx vitest run src/components/ModelSelect/ModelSelect.test.tsx` passes (13/13, including a new regression test that fails when the fix is reverted)
- [x] Consumer tests still green: `TeamInfo.test.tsx` + `key_edit_view.test.tsx` (53/53)
- [x] `npx tsc --noEmit` introduces zero new type errors (455 pre-existing, unchanged with this diff)
- [x] Scope isolated: 3 files, no new dependencies, no API/backend change
- [x] Comment `@greptileai` and get Confidence Score >= 4/5 before requesting maintainer review

## Type

🐛 Bug Fix

## Changes

### Problem

On the team edit form (Teams -> a team -> Settings -> Models), the model picker only ever shows a single row of selected models; anything past the first row collapses into a `+N more` chip. A team with many models is effectively unreadable. The virtual-key edit form does not have this problem; its picker wraps every selected model across as many rows as needed, which is the behavior users expect.

### Root cause

Both forms render an antd multi-select, but the team form goes through the shared `ModelSelect` component, which sets `maxTagCount="responsive"`. That prop forces all selected tags onto one row and folds the overflow into the `+N more` placeholder. The key edit form (`key_edit_view.tsx`) uses a plain `Select mode="multiple"` with no `maxTagCount`, so antd's default wrapping applies and every tag is visible.

`ModelSelect` is shared by the team, organization, access-group and user model pickers, so they all inherited the single-row behavior.

### Fix

Drop `maxTagCount="responsive"` (and the now-unused `maxTagPlaceholder` / `Tooltip`) from `ModelSelect` so selected tags wrap, matching the key edit form. To keep the picker from growing without bound when a team has a large model list, add a scoped class `model-select-multi` whose `.ant-select-selector` is capped at `132px` (about four to five rows) with `overflow-y: auto`, so the selection area scrolls past that height.

This applies to every `ModelSelect` consumer (team, organization, access group, user), which all had the same one-row limitation; the behavior now converges with the virtual-key picker.

### Tests

Replaced the obsolete `maxTagPlaceholder` test with a regression test asserting `ModelSelect` passes `className="model-select-multi"` and does not set `maxTagCount`. Verified by mutation: re-adding `maxTagCount="responsive"` or removing the class makes the test fail.

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/components/ModelSelect/ModelSelect.tsx` | Remove `maxTagCount="responsive"` + `maxTagPlaceholder` + unused `Tooltip` import; add `className="model-select-multi"` so tags wrap |
| `ui/litellm-dashboard/src/app/globals.css` | Add `.model-select-multi .ant-select-selector` rule capping height at 132px with vertical scroll |
| `ui/litellm-dashboard/src/components/ModelSelect/ModelSelect.test.tsx` | Update antd mock to expose `className` / `maxTagCount`; replace the placeholder test with a wrap-behavior regression test |

## Screenshots / Proof of Fix

UI change. To verify on a running proxy:

1. Open `http://localhost:4000/ui/?page=teams`
2. Click a team that has several models, go to the Settings tab and click Edit
3. Open the Models field: selected models now wrap across multiple rows; once they exceed ~4-5 rows the box scrolls instead of staying on one line
4. Cross-check `http://localhost:4000/ui/?page=api-keys` -> edit a key -> Models, which already wrapped; both pickers now behave the same
