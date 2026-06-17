# Azure Container Apps Job — secretless managed-identity scheduling

> [!IMPORTANT]
> **The schema blocker that held this up is now resolved.** As of
> **PAX v1.11.5** (and **v1.11.6**, the current release) PAX embeds the
> **v4.0.0** CopilotInteraction processor and a new **`-Dashboard AIBV`** switch
> that produces the AI Business Value rollup **natively** — the same 50-column
> profile the AIBV PBIT consumes. A custom container layer is **no longer
> needed**: you can run PAX's own container image directly.
>
> What remains is to **commit and test** the deployment, so until the files in
> the table below land here, the supported way to schedule the SharePoint
> refresh is still the **app registration** path documented in the
> [folder README](../README.md#authentication) (via
> [`Register-TaskScheduler.ps1`](../scripts/Register-TaskScheduler.ps1)).
> Managed identity is an **alternative** to that app registration, not an
> addition.

## What changed (PAX v1.11.5 / v1.11.6)

| | Before (PAX ≤ v1.11.4) | Now (PAX ≥ v1.11.5) |
|---|---|---|
| Embedded rollup processor | v3.1.0 (33-column schema) | **v4.0.0** (50-column AIBV schema) |
| AIBV rollup | Not available in PAX — needed this repo's separate [`Purview_CopilotInteraction_Processor_v4.0.0.py`](../scripts/Purview_CopilotInteraction_Processor_v4.0.0.py) | Built in — select with **`-Dashboard AIBV`** (auto-enables `-Rollup`) |
| Container story | Custom image layering the v4.0.0 processor over PAX | **Vanilla PAX image** ([`PAX.Dockerfile`](https://github.com/microsoft/PAX/blob/release/fabric_resources/Dockerfile/PAX.Dockerfile)) — no layer needed |

> [!NOTE]
> PAX's `-Dashboard AIBV` runs the **same** v4.0.0 processor this folder shipped;
> it was upstreamed into PAX. A one-time column/row diff of a PAX
> `-Dashboard AIBV` rollup against this repo's standalone processor output is
> still worth doing as a validation step before cutting over (see the checklist).

## Target design (no custom layer)

Run Microsoft PAX's **own** container as an ACA Job — nothing in this folder needs
to be baked into an image:

1. **Image** — build/push `microsoft/PAX`'s
   [`Dockerfile/PAX.Dockerfile`](https://github.com/microsoft/PAX/blob/release/fabric_resources/Dockerfile/PAX.Dockerfile)
   to your ACR (or pull a published tag).
2. **Job command** — invoke PAX with the AIBV dashboard, managed-identity auth,
   and a SharePoint document-library `-OutputPath`:

   ```text
   -Auth        ManagedIdentity
   -TenantId    <tenant-guid>
   -Dashboard   AIBV                 # embedded v4.0.0 rollup; auto-enables -Rollup
   -IncludeUserInfo                  # Entra users + MAC licensing (AIBV needs both)
   -Days        30                   # or -StartDate / -EndDate
   -OutputPath  "https://<tenant>.sharepoint.com/sites/<site>/<library>/AIBV"
   ```
3. **Deploy** — use PAX's own
   [`Deploy/Deploy-PAXAcaJob.ps1`](https://github.com/microsoft/PAX/blob/release/fabric_resources/Deploy/Deploy-PAXAcaJob.ps1)
   (ACR build/push + ACA Job + managed identity + cron trigger).
4. **Permissions** — grant the managed identity the same Microsoft Graph
   application permissions the app-registration path uses, plus SharePoint write.
   PAX's [`Prereqs/Grant-PAXPermissions.ps1`](https://github.com/microsoft/PAX/blob/release/fabric_resources/Prereqs/Grant-PAXPermissions.ps1)
   covers the Graph + Azure roles; the SharePoint `Sites.Selected` grant is
   already handled by
   [`../scripts/ProvisionSiteAccess-SP-AppReg.ps1`](../scripts/ProvisionSiteAccess-SP-AppReg.ps1)
   (point it at the managed identity's client ID instead of the app registration).

Because PAX emits AIBV directly, the in-container flow is a **single step**
(PAX → SharePoint) rather than the old two-step (PAX → v4.0.0 processor →
SharePoint).

## Remaining work to ship this

- [ ] **Validate** a PAX `-Dashboard AIBV` rollup matches this repo's standalone
      v4.0.0 output (column set + a row-level spot check).
- [ ] **Filename mapping.** The PBIT parameters point at fixed names
      (`copilot_interactions_rollup.csv`, `copilot_users_rollup.csv`); PAX writes
      timestamped rollup filenames. Decide between (a) pointing the PBIT at the
      PAX names, (b) a small post-upload rename, or (c) a PAX fixed-name option —
      the Task Scheduler path currently handles this in
      [`../scripts/Upload-Rollups-SharePoint.ps1`](../scripts/Upload-Rollups-SharePoint.ps1).
- [ ] **Permissions for the managed identity** — Graph app roles
      (`AuditLogsQuery.Read.All`, `Reports.Read.All`, `User.Read.All`,
      `Organization.Read.All`) **+** SharePoint write (`Sites.Selected` on the
      target library, or `Sites.ReadWrite.All` / `Files.ReadWrite.All` + Edit /
      Contribute on the folder).
- [ ] **Commit + test** the ACA Job end-to-end (a 1-day run validates audit read,
      SharePoint write, and managed-identity sign-in in minutes).

## What this folder will contain when shipped

| File | Purpose |
|---|---|
| `Deploy-AcaJob.ps1` | One-shot deploy: ACR build/push of PAX's image + ACA Job + managed identity + cron. A thin wrapper over PAX's [`Deploy-PAXAcaJob.ps1`](https://github.com/microsoft/PAX/blob/release/fabric_resources/Deploy/Deploy-PAXAcaJob.ps1), pre-set with `-Dashboard AIBV` and a SharePoint `-OutputPath`. |
| `Grant-Permissions.ps1` | One-time per-tenant: Graph app roles + admin consent + `Sites.Selected` grant for the managed identity. |
| `job.env.example` | Example job parameters (tenant, site/library path, schedule). |

> No `Dockerfile` or `entrypoint.ps1` is listed any more — with `-Dashboard AIBV`
> the stock PAX image is used as-is.

## Until this lands

Use one of the scheduling options the [folder README](../README.md#schedule-it)
documents (both authenticate with the app registration):

- **Windows Task Scheduler** — see
  [`../scripts/Register-TaskScheduler.ps1`](../scripts/Register-TaskScheduler.ps1)
- **GitHub Actions** — a `.yml` workflow that runs `Run-PAX-AIBV.ps1` +
  `Upload-Rollups-SharePoint.ps1` on a `schedule:` cron

## Tracking

Open an issue tagged `azure-container` if you'd like to help land this.
