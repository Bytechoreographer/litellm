# PR: fix(ui): credential list stays stale on Add Model page after adding a credential

> **Branch**: `Bytechoreographer:fix/credential-list-stale-on-add-model`
> **Target**: `BerriAI:litellm_oss_branch`
> **PR link**: https://github.com/Bytechoreographer/litellm/pull/new/fix/credential-list-stale-on-add-model

---

## Relevant issues

<!-- No open issue found; reproduced locally. -->

## Pre-Submission checklist

- [x] `npm run test` passes for affected files (5/5)
- [x] Scope is isolated: 4 files changed, no new dependencies
- [ ] Comment `@greptileai` and get Confidence Score ≥ 4/5 before requesting maintainer review

## Type

🐛 Bug Fix

## Changes

### Root cause

After adding, editing, or deleting a credential in the **LLM Credentials** tab,
the **Existing Credentials** dropdown on the **Add Model** tab does not reflect
the change until a full page refresh.

`CredentialsPanel` calls `refetch()` on its own `useQuery` observer after each
mutation, which refreshes the panel's own list. However, `ModelsAndEndpointsView`
holds a separate `useCredentials()` subscription and passes the result down as
`credentialsList → AddModelTab → AddModelForm → AntdSelect options`. That
subscription is never notified, so the dropdown stays stale:

```
ModelsAndEndpointsView
  └─ const { data } = useCredentials()     ← never sees the new credential
  └─ <AddModelTab credentials={credentialsList} />
       └─ <AddModelForm credentials={credentials} />
            └─ <AntdSelect options={[...credentials]} />   ← stale list
```

**Reproduce:**
1. Open **LLM Credentials** tab → add a new credential
2. Switch to **Add Model** tab → open the **Existing Credentials** dropdown
3. Newly created credential is absent ✗
4. Full page refresh → now it appears ✓

### Fix

Replace `refetch()` with `queryClient.invalidateQueries({ queryKey: credentialsKeys.all })`,
the established cross-component cache invalidation pattern used throughout this
codebase (`accessGroupKeys`, `projectKeys`, `cloudZeroSettingsKeys`, `keyKeys`, …).

`invalidateQueries` marks the shared React Query cache entry as stale and triggers
a background refetch for **all active subscribers** — including
`ModelsAndEndpointsView` — so the dropdown updates immediately after any mutation.

```diff
- const { data: credentialsResponse, refetch: refetchCredentials } = useCredentials();
+ const { data: credentialsResponse } = useCredentials();
+ const queryClient = useQueryClient();

  // in each mutation handler (add / update / delete):
- await refetchCredentials();
+ await queryClient.invalidateQueries({ queryKey: credentialsKeys.all });
```

`credentialsKeys` is exported from `useCredentials.ts` so consumers can reference
the canonical query key without duplicating the string.

### Additional fixes in the same files

**`credentials.tsx`** — remove dead `Form.useForm()` instance that was never
connected to any `<Form form={...}>`, causing the Ant Design console warning
*"Instance created by `useForm` is not connected to any Form element"*.

**`AddModelForm.tsx`** — fix Ant Design console warning
*"`value` in Select options should not be `null`"*: the "None" option used
`value: null`, which Ant Design v5 rejects. Changed to `value: ""` and removed
the corresponding `initialValue={null}` from `Form.Item` (no-selection is
correctly represented by `undefined`). The submit handler already deletes
`litellm_credential_name` from params when the value is absent, so the empty
string is handled safely.

### Files changed

| File | Change |
|------|--------|
| `ui/litellm-dashboard/src/app/(dashboard)/hooks/credentials/useCredentials.ts` | Export `credentialsKeys` so consumers can reference the canonical query key |
| `ui/litellm-dashboard/src/components/model_add/credentials.tsx` | Replace `refetch()` with `invalidateQueries` on all three mutation handlers; remove dead `Form.useForm()` + `Form` import |
| `ui/litellm-dashboard/src/components/add_model/AddModelForm.tsx` | Fix `null` option value in credential `AntdSelect`; remove `initialValue={null}` |
| `ui/litellm-dashboard/src/components/model_add/credentials.test.tsx` | Remove stale `refetch` stub; export `credentialsKeys` in mock; add test verifying `invalidateQueries` is called on credential add |
