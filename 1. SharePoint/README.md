# SharePoint deployment

The simplest way to run the dashboard with **scheduled refresh** and **no Fabric capacity**.
PowerShell (using the Microsoft Graph API) extracts your Copilot data to CSVs, drops them into a
SharePoint library, and Power BI Service refreshes straight from there — **no gateway needed**.

> Need millions of events or multi‑year history? Use [`../2. Fabric/`](../2.%20Fabric/) instead.

## What's in this folder

| Item | Purpose |
|---|---|
| `AI Business Value Dashboard - SharePoint.pbit` | **The one template.** Open in Power BI Desktop, point each parameter at your SharePoint CSV, publish. |
| `scripts/` | The PowerShell extractors. `*-AppReg.ps1` = unattended (for scheduling); lower‑case names = interactive (admin runs by hand). See [`scripts/README.md`](scripts/README.md). |
| `azure/` | Optional Bicep + Azure Automation runbooks to run the scripts on a schedule. See [`azure/README.md`](azure/README.md). |

## How it works

```
PowerShell (scheduled: Azure Automation / Task Scheduler)
        ↓  pulls from Microsoft Graph + Purview
Each script writes ONE fixed-name CSV per source, OVERWRITING last run's file
        ↓  uploads to a SharePoint document library
Power BI Service scheduled refresh reads those SharePoint URLs
```

**Key design — one fixed file per source.** Each script overwrites the *same* file every run
(`copilot_interactions.csv`, `copilot_licensed_users.csv`, `org_data.csv`). The template points at
those single URLs, so there's **no folder iteration** — which avoids the privacy‑firewall and
stray‑file errors that folder‑based refreshes are prone to.

## Data sources

| Source | Required? | Script | Fixed CSV |
|---|---|---|---|
| Copilot interactions (audit logs) | ✅ Core | `CreateAuditLogQuery-AppReg.ps1` → `GetCopilotInteractions-SP-AppReg.ps1` | `copilot_interactions.csv` |
| Licensed users | ✅ Core | `GetCopilotUsers-SP-AppReg.ps1` | `copilot_licensed_users.csv` |
| Org data (department / manager) | ✅ Core | `Get-EntraOrgData-SP-AppReg.ps1` | `org_data.csv` |
| Agents 365 | ⬜ Optional | `scripts/interactive/Get-Agents365Registry.ps1` | (your export) |
| Agent transcripts (Copilot Studio) | ⬜ Optional | parsed transcripts folder/CSV | (your export) |
| Credit consumption (billing) | ⬜ Optional | Power Platform Admin Center export | the 3 `EntitlementConsumption…` CSVs |
| Product feedback | ⬜ Optional | M365 Admin Center → Health → Product Feedback export | `feedback.csv` |

**Optional sources just add pages.** Leave their parameters blank and those pages stay empty — the
core dashboard works without them. (Credit consumption and product feedback are **export‑only** in
Microsoft’s portals — there is no API — so you upload the CSV to SharePoint and point the parameter
at it, same as the core files.)

## Quick start

### 1. One‑time setup (per tenant)

1. **Register an Entra app** with these Microsoft Graph **Application** permissions (grant admin consent):
   `AuditLogsQuery.Read.All`, `Reports.Read.All`, `User.Read.All`, `Organization.Read.All`, `Sites.Selected`.
   Note the **tenant ID, client ID, client secret**.
2. **Pick a SharePoint site** for the CSVs (note the host, e.g. `contoso.sharepoint.com`, and library path).
3. **Grant the app write access to just that site** (`Sites.Selected`):
   ```powershell
   cd scripts/provisioning
   .\ProvisionSiteAccess-SP-AppReg.ps1 -TenantId "<tenant-id>" -SiteHost "<tenant>.sharepoint.com" `
       -AppClientId "<client-id>" -AppDisplayName "<app-name>"
   ```
   It prints the **SiteId** and **DriveId** the upload scripts need.

### 2. Run / schedule the extractors

In order (≈30‑min gap after the create step while Purview builds the query):

1. `CreateAuditLogQuery-AppReg.ps1` — starts the Purview audit query
2. *(wait ~30 mins)*
3. `GetCopilotInteractions-SP-AppReg.ps1` — fetches + flattens (15 cols) → `copilot_interactions.csv`
4. `GetCopilotUsers-SP-AppReg.ps1` → `copilot_licensed_users.csv`
5. `Get-EntraOrgData-SP-AppReg.ps1` → `org_data.csv`

To automate, see [`azure/README.md`](azure/README.md) (Bicep + Automation Account, managed identity).

### 3. Connect the template

1. Open **`AI Business Value Dashboard - SharePoint.pbit`** in Power BI Desktop.
2. **Transform data → Edit parameters** → set each to its SharePoint file URL:

   | Parameter | Value |
   |---|---|
   | Copilot Interactions File | `https://<tenant>.sharepoint.com/<site>/<library>/copilot_interactions.csv` |
   | Copilot Licensed Users | `.../copilot_licensed_users.csv` |
   | Org Data File | `.../org_data.csv` |
   | Agent 365 *(optional)* | blank, or a SharePoint URL to your Agents export |
   | Copilot Agent Transcripts Folder *(optional)* | blank, or the transcripts folder |
   | Product Feedback *(optional)* | blank, or `.../feedback.csv` |
   | Credit Consumption – Tenant/Agent/User *(optional)* | blank, or the matching `EntitlementConsumption…` CSV URL |

3. **Load** → **Publish** to a Power BI workspace.
4. Service → dataset **Settings → Data source credentials** → sign in to SharePoint; set **Privacy: None**.
5. **Scheduled refresh** → enable, set to run after your script schedule (e.g. scripts 02:00, dataset 04:00).

## Required permissions

| Permission | Type | Used by |
|---|---|---|
| `AuditLogsQuery.Read.All` | Application | Create / Get interactions |
| `Reports.Read.All` | Application | Licensed users |
| `User.Read.All` | Application | Org data |
| `Organization.Read.All` | Application | (implicit in some flows) |
| `Sites.Selected` | Application | All uploads (granted **per site** by ProvisionSiteAccess) |

## Common errors

| Symptom | Likely cause | Fix |
|---|---|---|
| `403 Forbidden` on upload | App lacks site permission | Re‑run `ProvisionSiteAccess-SP-AppReg.ps1` |
| `404 Not Found` on PUT | Folder path doesn't exist | Create the folder in SharePoint, or use `-FolderPath ""` for the drive root |
| `ClientSecretCredential authentication failed` | Secret expired/mistyped | Generate a fresh secret, re‑run |
| `0 records returned` | Missing `AuditLogsQuery.Read.All` consent | Re‑grant in Entra → API permissions |
| Masked UPNs (32‑char hex) | M365 report concealment is on | Admin → Settings → Org settings → Reports → untick "Display concealed names" |
| Refresh hits 1 GB / 2‑hour caps | Volume too high for Pro/shared | Move to [`../2. Fabric/`](../2.%20Fabric/) |
