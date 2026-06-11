# Scripts (SharePoint rollup edition)

Three scripts you actually run, plus one Python processor invoked by the wrapper:

| Script | When you run it |
|---|---|
| `ProvisionSiteAccess-SP-AppReg.ps1` | **Once per site.** Grants your app reg `Sites.Selected` write access to a specific SharePoint site. Prints `SiteId` + `DriveId`. |
| `Run-PAX-AIBV.ps1` | **Every refresh.** Auto-clones [microsoft/PAX](https://github.com/microsoft/PAX), extracts the audit data, runs the v4.0.0 Python processor, drops two rollup CSVs + a manifest into `.\processed\`. |
| `Upload-Rollups-SharePoint.ps1` | **Every refresh, after `Run-PAX-AIBV.ps1`.** Uploads the two rollup CSVs to fixed names in your SharePoint library (overwrites). |
| `Register-TaskScheduler.ps1` | **Optional, once.** Registers the two refresh scripts as a single daily Windows Scheduled Task. |
| `Purview_CopilotInteraction_Processor_v4.0.0.py` | Called by `Run-PAX-AIBV.ps1`. Not invoked directly in normal use. |
| `Get-Agents365Registry.ps1` | Optional, ad-hoc. Exports Agents 365 registry for the dashboard's Agents 365 page. |

Prereqs: PowerShell 7+ (`pwsh`), Python 3.10+, `git` on PATH.

---

## 1. `ProvisionSiteAccess-SP-AppReg.ps1`

One-time, per SharePoint site. The app reg needs the *tenant-level* Graph
permission `Sites.Selected` (admin-consented). This script then grants it the
*per-site* write permission Graph needs to PUT files.

```powershell
.\ProvisionSiteAccess-SP-AppReg.ps1 `
    -TenantId       "<tenant-id>" `
    -SiteHost       "<tenant>.sharepoint.com" `
    -AppClientId    "<client-id>" `
    -AppDisplayName "<app-name>"
```

Save the **SiteId** (`<host>,<siteguid>,<webguid>`) and **DriveId** (`b!...`)
it prints — both are required by `Upload-Rollups-SharePoint.ps1`.

---

## 2. `Run-PAX-AIBV.ps1`

The wrapper. Drives PAX end-to-end, then runs the AIBV v4.0.0 processor
(which produces the 50-col schema the PBIT expects — PAX's embedded v3.1.0
processor only emits 33 cols).

```powershell
.\Run-PAX-AIBV.ps1 `
    -TenantId   <tenant-id> `
    -ClientId   <client-id> `
    [-ClientSecret <secret>] `
    [-Days 7] `
    [-WorkRoot .] `
    [-PaxBranch release] `
    [-SkipProcessor]
```

**Secret resolution order:**
1. `-ClientSecret` parameter
2. `$env:AIBV_CLIENT_SECRET`
3. Windows Credential Manager target `PAX-AIBV-<TenantId>`
   (stash it once with `cmdkey /generic:PAX-AIBV-<tenant> /user:app /pass:<secret>`)
4. Interactive secure-string prompt

**What lands on disk:**

```
<WorkRoot>/
  pax/                                     # microsoft/PAX clone (first run only)
  raw/
    Purview_Audit_UsageActivity_CopilotInteraction_<ts>.csv
    EntraUsers_MAClicensing_<ts>.csv
  processed/
    <purview-stem>_Interactions_<ts>.csv   # 50-col AIBV
    <entra-stem>_Users_<ts>.csv            # 51-col AIBV
    rollup-manifest.json                   # paths + timings for the upload step
```

`-Days 7` is a sensible default for daily incremental refresh. For first-time
backfill, try `-Days 30` or `-Days 90`; PAX partitions a 90-day window into
~180 × 12 h chunks, 10 concurrent.

---

## 3. `Upload-Rollups-SharePoint.ps1`

Reads the manifest (or accepts the two CSVs directly), uploads each to a
**fixed** name in your SharePoint library:

```
copilot_interactions_rollup.csv
copilot_users_rollup.csv
```

Fixed names because the AIBV PBIT points at single URLs — each upload overwrites
the previous file, so refresh has nothing to choose between.

```powershell
.\Upload-Rollups-SharePoint.ps1 `
    -Manifest    .\processed\rollup-manifest.json `
    -TenantId    <tenant-id> `
    -ClientId    <client-id> `
    [-ClientSecret <secret>] `
    -SiteId      '<host>,<siteguid>,<webguid>' `
    -DriveId     'b!...' `
    [-FolderPath /AIBV]
```

Or skip the manifest and pass the CSVs directly:

```powershell
.\Upload-Rollups-SharePoint.ps1 `
    -InteractionsCsv .\processed\..._Interactions_....csv `
    -UsersCsv        .\processed\..._Users_....csv `
    -TenantId        <tenant-id> `
    -ClientId        <client-id> `
    -SiteId          '...' `
    -DriveId         '...'
```

Files >4 MB use a Graph upload session (chunked) automatically. Typical 30-day
rollup CSVs are well under that.

---

## End-to-end (typical daily refresh)

```powershell
cd 'C:\path\to\AI-Business-Value-Dashboard\2. SharePoint\scripts'

# Day one only:
.\ProvisionSiteAccess-SP-AppReg.ps1 -TenantId $t -SiteHost contoso.sharepoint.com `
    -AppClientId $c -AppDisplayName 'AIBV-Rollup'

# Every refresh:
.\Run-PAX-AIBV.ps1               -TenantId $t -ClientId $c -Days 30
.\Upload-Rollups-SharePoint.ps1  -TenantId $t -ClientId $c `
    -Manifest .\processed\rollup-manifest.json `
    -SiteId 'contoso.sharepoint.com,...' -DriveId 'b!...' -FolderPath '/AIBV'
```

Wire those last two lines into Task Scheduler / GitHub Actions / Hybrid Worker
and you have scheduled refresh. For Task Scheduler the easiest path is the
included `Register-TaskScheduler.ps1` helper:

```powershell
.\Register-TaskScheduler.ps1 `
    -TenantId   <tenant-id> -ClientId <client-id> `
    -SiteId     'contoso.sharepoint.com,...' `
    -DriveId    'b!...' `
    -FolderPath '/AIBV' `
    -RunAt      '02:00'
```

See the [folder README](../README.md#scheduling) for the full trade-offs across
Task Scheduler / GitHub Actions / Azure Container Apps.
