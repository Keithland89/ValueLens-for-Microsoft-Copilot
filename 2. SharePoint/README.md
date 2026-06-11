# SharePoint deployment (rollup edition)

The simplest way to run the AI Business Value Dashboard with **scheduled refresh**
and **no Fabric capacity**.

[Microsoft PAX](https://github.com/microsoft/PAX) pulls Copilot audit data from
your tenant in parallel partitions, a Python processor classifies every
interaction into the 50-column AIBV rollup schema, the two rollup CSVs land in
SharePoint, and Power BI Service refreshes straight from there — **no gateway
needed**.

> Need millions of events or multi-year history? Use [`../1. Fabric/`](../1.%20Fabric/) instead.

---

## What changed from the v1 flatten flow

| | **v1 flatten** *(archived)* | **v2 rollup** *(this folder)* |
|---|---|---|
| Audit extract | 4 sequential scripts, 30-min wait after `CreateAuditLogQuery` | [PAX](https://github.com/microsoft/PAX) — single command, 12 h partitions, up to 10 in parallel |
| Typical 7-day extract | ~45–60 min wall time | ~5–10 min on a quiet tenant |
| Classification | Power Query at refresh (15 fixed columns) | Python at extract (50 AIBV columns) → PBI just types and reads |
| Resumability | None | PAX has per-partition retry + circuit breakers |
| Cowork / agent tagging | None | Pre-tagged in `Agent Filter` column |
| PBIT params | 3 fixed CSVs | Same 3 CSVs (2 rollups + optional Agents 365) |
| Files in folder | 7 PS scripts + bicep | 1 wrapper + 1 Python processor + 2 helpers |

The v1 flow still works — it's archived under
[`../archive/2. SharePoint (v1-flatten)/`](../archive/) for anyone running it.

---

## What's in this folder

| Item | Purpose |
|---|---|
| `AI Business Value Dashboard - SharePoint.pbit` | **The one template.** Open in Power BI Desktop, point each parameter at your SharePoint CSV, publish. |
| `scripts/Run-PAX-AIBV.ps1` | One command: clones PAX on first run, extracts, runs the v4.0.0 processor, emits the two rollup CSVs + a manifest. |
| `scripts/Upload-Rollups-SharePoint.ps1` | Uploads the two rollup CSVs to your SharePoint library at **fixed names** (overwrite-in-place). |
| `scripts/Purview_CopilotInteraction_Processor_v4.0.0.py` | The AIBV rollup processor. 50-col Interactions + 51-col Users schema, pre-classified for the PBIT. |
| `scripts/ProvisionSiteAccess-SP-AppReg.ps1` | One-time helper: grants your app reg `Sites.Selected` write access to the target SharePoint site. Prints the `SiteId` + `DriveId` the upload script needs. |
| `scripts/Get-Agents365Registry.ps1` | Optional: exports Agents 365 registry for the dashboard's Agents 365 page. |

See [`scripts/README.md`](scripts/README.md) for the full parameter reference.

---

## How it works

```
Run-PAX-AIBV.ps1
    ├── git clone microsoft/PAX (first run only)
    ├── PAX extracts raw audit + Entra → raw/ folder
    └── v4.0.0 processor → processed/
            ├── *_Interactions_<timestamp>.csv  (50 cols, AIBV)
            ├── *_Users_<timestamp>.csv         (51 cols, AIBV)
            └── rollup-manifest.json

Upload-Rollups-SharePoint.ps1
    └── Graph PUT (Sites.Selected) → SharePoint library
            ├── copilot_interactions_rollup.csv  (FIXED name, overwrites)
            └── copilot_users_rollup.csv         (FIXED name, overwrites)

Power BI Service scheduled refresh
    └── reads those two fixed SharePoint URLs
```

**Why fixed file names?** The PBIT points at single URLs, not a folder. Each
upload overwrites the previous file. No folder iteration → no privacy-firewall
fights, no stray-file errors, no permission re-prompts.

---

## Data sources

| Source | Required? | Where it comes from |
|---|---|---|
| Copilot interactions (audit logs) | ✅ Core | PAX → `copilot_interactions_rollup.csv` |
| Org + licensed users | ✅ Core | PAX (`-IncludeUserInfo`) → `copilot_users_rollup.csv` |
| Agents 365 | ⬜ Optional | `Get-Agents365Registry.ps1` → your own SharePoint URL |

Optional sources (credit consumption, product feedback) are Fabric-only — they
live in the [`../1. Fabric/`](../1.%20Fabric/) path.

---

## Quick start

### 1. One-time setup (per tenant)

1. **Register an Entra app** with these Microsoft Graph **Application**
   permissions (grant admin consent):

   - `AuditLogsQuery.Read.All`
   - `Reports.Read.All`
   - `User.Read.All`
   - `Organization.Read.All`
   - `Sites.Selected`

   Note the **tenant ID**, **client ID**, **client secret**.

2. **Pick a SharePoint site** for the rollup CSVs (note the host, e.g.
   `contoso.sharepoint.com`, and library/folder path).

3. **Grant the app write access to just that site** (`Sites.Selected`):

   ```powershell
   cd scripts
   .\ProvisionSiteAccess-SP-AppReg.ps1 `
       -TenantId       "<tenant-id>" `
       -SiteHost       "<tenant>.sharepoint.com" `
       -AppClientId    "<client-id>" `
       -AppDisplayName "<app-name>"
   ```

   Save the **SiteId** and **DriveId** it prints — `Upload-Rollups-SharePoint.ps1`
   needs both.

4. **Install prereqs** on the box that'll run the extract:

   - PowerShell 7+ (`pwsh`)
   - Python 3.10+
   - `git`

### 2. Run the extract

```powershell
cd scripts

# Stash the secret once (Windows Credential Manager — optional)
cmdkey /generic:PAX-AIBV-<tenant-id> /user:app /pass:<client-secret>

# Pull a 30-day window and produce the rollup CSVs
.\Run-PAX-AIBV.ps1 `
    -TenantId <tenant-id> `
    -ClientId <client-id> `
    -Days 30
```

Output: `.\processed\*_Interactions_<ts>.csv`, `.\processed\*_Users_<ts>.csv`,
and `rollup-manifest.json`.

### 3. Upload to SharePoint

```powershell
.\Upload-Rollups-SharePoint.ps1 `
    -Manifest    .\processed\rollup-manifest.json `
    -TenantId    <tenant-id> `
    -ClientId    <client-id> `
    -SiteId      '<host>,<siteguid>,<webguid>' `
    -DriveId     'b!...' `
    -FolderPath  '/AIBV'
```

Files land as `copilot_interactions_rollup.csv` + `copilot_users_rollup.csv`,
overwriting whatever was there.

### 4. Connect the template

1. Open **`AI Business Value Dashboard - SharePoint.pbit`** in Power BI Desktop.
2. **Transform data → Edit parameters** → set each to its SharePoint URL:

   | Parameter | Value |
   |---|---|
   | Copilot Interactions File | `https://<tenant>.sharepoint.com/.../copilot_interactions_rollup.csv` |
   | Org Data File | `https://<tenant>.sharepoint.com/.../copilot_users_rollup.csv` |
   | Agent 365 *(optional)* | blank, or a SharePoint URL to your Agents 365 export |

3. **Load** → **Publish** to a Power BI workspace.
4. Service → dataset **Settings → Data source credentials** → sign in to
   SharePoint; set **Privacy: None**.
5. **Scheduled refresh** → enable, set to run after your extract schedule
   (e.g. extract 02:00, refresh 04:00).

---

## Scheduling

PAX itself ships no automation guidance for the SharePoint flow. Three options
in this folder, in order of operational complexity:

### 1. Windows Task Scheduler — easiest

For anyone with a Windows host that's always on (jumpbox, VM, or even a
shared workstation). One helper script registers both extract + upload as a
single daily task:

```powershell
cd scripts

# Stash the secret once (Credential Manager — the scripts read this at runtime)
cmdkey /generic:PAX-AIBV-<tenant-id> /user:app /pass:<client-secret>

# Register the daily task (run elevated)
.\Register-TaskScheduler.ps1 `
    -TenantId   <tenant-id> `
    -ClientId   <client-id> `
    -SiteId     '<host>,<siteguid>,<webguid>' `
    -DriveId    'b!...' `
    -FolderPath '/AIBV' `
    -RunAt      '02:00'
```

Pass `-RunAsUser DOMAIN\svc_aibv` to run under a service account whether or not
that user is signed in. Test the registered task immediately with
`Start-ScheduledTask -TaskName AIBV-Rollup-Refresh`.

### 2. GitHub Actions — public-repo / community deployments

A scheduled workflow (`schedule:` cron) running the same two scripts on the
ubuntu-latest runner. Good for OSS scenarios and demo tenants. Secrets live
in repo settings. *(Workflow YAML to be added in a follow-up PR.)*

> Beware: many enterprise tenants block app-auth from GitHub-hosted runner
> IP ranges via Conditional Access. Test it can reach Graph before relying
> on it for prod.

### 3. Azure Container Apps Job — enterprise (WIP)

For unattended scheduled runs with managed identity and no long-lived
secrets. The [`azure-container/`](./azure-container/) folder describes the
planned shape (thin custom image layered over PAX's prebuilt container);
**implementation is not yet shipped**. Until it lands, enterprises should use
Task Scheduler on an Azure VM with managed identity, or run the
[`scripts/`](./scripts/) directly from an Azure Automation Hybrid Worker.

> The old v1 `azure-automation/` bicep (native cloud-sandbox runbooks) does
> **not** carry forward — Azure Automation can't mix PowerShell and Python in
> one runbook, and PAX is too large to chunk. It's preserved in
> [`../archive/2. SharePoint (v1-flatten)/azure-automation/`](../archive/) for
> reference only.

---

## Required permissions

| Permission | Type | Used by |
|---|---|---|
| `AuditLogsQuery.Read.All` | Application | PAX — audit log queries |
| `Reports.Read.All` | Application | PAX — licensed users |
| `User.Read.All` | Application | PAX — org data |
| `Organization.Read.All` | Application | PAX — tenant context |
| `Sites.Selected` | Application | Upload (granted **per site** by `ProvisionSiteAccess`) |

---

## Common errors

| Symptom | Likely cause | Fix |
|---|---|---|
| `git: command not found` | Wrapper expects git on PATH | Install git and retry |
| `python: command not found` | Wrapper expects python on PATH | Install Python 3.10+ |
| PAX `404` on `/v1.0/security/auditLog/queries` | Tenant only exposes `/beta` | PAX auto-falls back; you'll see one line of noise then it continues |
| `0 records returned` | Missing `AuditLogsQuery.Read.All` consent | Re-grant in Entra → API permissions |
| Masked UPNs (32-char hex) | M365 report concealment is on | Admin → Settings → Org settings → Reports → untick "Display concealed names" |
| `403 Forbidden` on upload | App lacks site permission | Re-run `ProvisionSiteAccess-SP-AppReg.ps1` |
| `404 Not Found` on PUT | `-FolderPath` doesn't exist | Create the folder in SharePoint or use `/` for drive root |
| Refresh hits 1 GB / 2-hour caps | Volume too high for Pro/shared | Move to [`../1. Fabric/`](../1.%20Fabric/) |
| Cowork interactions tagged `Agents` instead of `Cowork` | Running an older processor | Make sure `Purview_CopilotInteraction_Processor_v4.0.0.py` (or later) is the one being called |
