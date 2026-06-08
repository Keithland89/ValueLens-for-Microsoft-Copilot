# Fabric / Lakehouse deployment

> **Not just Fabric.** This folder is named "Fabric" because that's the simplest deployment, but the same PBIT + ingester notebooks also work on **Azure Databricks**, **Synapse Spark**, **Azure SQL / Fabric Warehouse**, or **ADLS Gen2** with no real changes — see [Alternative platforms](#alternative-platforms) below.

The recommended path for tenants with Fabric capacity (or Premium / PPU). All three input tables (audit interactions, licensed users, org data) are populated by **Direct Ingester** notebooks that authenticate to Microsoft Graph with an app registration and write Delta tables directly into the Lakehouse — no PowerShell, no raw-CSV landing step. The Power BI dataset becomes a thin pass-through against those Delta tables (or zero-copy with Direct Lake mode). Heavy JSON parsing, column-variant detection, and joins all happen in Spark.

## What's in this folder

| Item | Purpose |
|---|---|
| [`AI-Business-Value-Dashboard-Fabric.pbit`](AI-Business-Value-Dashboard-Fabric.pbit) | The Power BI template (thin client — sources its tables from a Lakehouse SQL endpoint) |
| [`notebooks/Copilot_Audit_Log_Direct_Ingester.ipynb`](notebooks/Copilot_Audit_Log_Direct_Ingester.ipynb) | Calls the Graph audit-log API → `dbo.copilot_interactions_parsed` |
| [`notebooks/Copilot_Licensed_Users_Direct_Ingester.ipynb`](notebooks/Copilot_Licensed_Users_Direct_Ingester.ipynb) | Calls the Graph M365 active-user report → `dbo.copilot_licensed_users` |
| [`notebooks/Copilot_Org_Data_Direct_Ingester.ipynb`](notebooks/Copilot_Org_Data_Direct_Ingester.ipynb) | Calls Graph `/users` (with manager expand) → `dbo.copilot_org_data` |
| [`notebooks/Copilot_Agent_Transcript_Parser.ipynb`](notebooks/Copilot_Agent_Transcript_Parser.ipynb) | *(Optional)* Parses Dataverse conversation transcripts → the 6 agent tables (sessions, turns, errors, sub-agents, catalogue, performance) |
| [`notebooks/Copilot_Credit_Consumption_Ingester.ipynb`](notebooks/Copilot_Credit_Consumption_Ingester.ipynb) | *(Optional)* Lands the Power Platform message-credit CSV exports → 3 billing tables. **See the plain-language [`CREDIT-CONSUMPTION-SETUP.md`](CREDIT-CONSUMPTION-SETUP.md).** |
| [`notebooks/Copilot_ProductFeedback_Ingester.ipynb`](notebooks/Copilot_ProductFeedback_Ingester.ipynb) | *(Optional)* Lands the M365 Admin Center **product feedback** export (export-only, no API) → `dbo.user_feedback` (drives the User Feedback page). Pair with `flows/Copilot_ProductFeedback_Email_to_OneLake.json`. |
| [`notebooks/Copilot_Agent365_Lander.ipynb`](notebooks/Copilot_Agent365_Lander.ipynb) | *(Optional)* Lands the Agents 365 **export CSV** → `agents_365`. **Supported Agent 365 path.** |
| [`notebooks/Copilot_Agent365_Registry_Ingester_PREVIEW.ipynb`](notebooks/Copilot_Agent365_Registry_Ingester_PREVIEW.ipynb) | *(Optional · ⚠️ PREVIEW)* Pulls the live Agent 365 catalog from the **beta** Graph endpoint (delegated auth, Frontier-program + AI Admin only — **can't run unattended**). Use the lander above for production; this is for hands-on capability/permission detail in Frontier tenants. |
| [`flows/`](flows/) | *(Optional)* Power Automate flows that auto-land **export-only** sources (credit consumption, product feedback) into the Lakehouse. See [`flows/README.md`](flows/README.md). |
| [`CREDIT-CONSUMPTION-SETUP.md`](CREDIT-CONSUMPTION-SETUP.md) | **Non-technical, step-by-step** guide to switching on the optional credit-consumption billing pages. |
| [`archive/`](archive/) | The legacy two-stage flow (PowerShell → CSVs → Parser/Loader notebooks). Kept for migration reference only. See [`archive/README.md`](archive/README.md). |

> **Optional sources (Dataverse agents, credit consumption, product feedback, Agents 365)** are all
> gated by `Enable_*` toggle parameters and degrade to empty tables when absent — the core
> dashboard works without any of them. See [`../shared/docs/OPTIONAL-SOURCES.md`](../shared/docs/OPTIONAL-SOURCES.md).
> For the billing pages specifically, follow [`CREDIT-CONSUMPTION-SETUP.md`](CREDIT-CONSUMPTION-SETUP.md).

## When to use this path

| Pick this path if… | Pick another path instead if… |
|---|---|
| You have Fabric capacity (F2+ or trial) | Power BI Pro only with no Fabric / Premium → use [`1. SharePoint/`](../1.%20SharePoint/) |
| Audit volume > 100K events / week | Audit volume is small enough to refresh in Power BI dataset directly |
| You want scheduled, hands-off ingestion | You're happy running scripts ad-hoc |
| You hit the 1 GB dataset cap or 2-hour refresh timeout in Service | Refresh has always succeeded for you |

## Why pre-parsing matters

The default templates parse the `AuditData` JSON column inside the Power BI dataset's M-query. That works for small/medium tenants, but at scale it triggers three Service-side limits:

1. **Memory cap** — Pro/shared workspaces cap the dataset at 1 GB; peak refresh memory can be 3× that during JSON expansion
2. **Refresh timeout** — 2 hours on shared, 5 hours on Premium
3. **Power Query firewall** — `Formula.Firewall` errors when combining queries from different sources

Moving the parse into Fabric eliminates all three. The dataset becomes a thin pass-through against an already-flat Delta table.

## Architecture

```
Microsoft Graph                 Microsoft Graph                Microsoft Graph
(Office 365 audit logs)         (M365 active users report)     (/users + manager expand)
        ↓                               ↓                               ↓
Copilot_Audit_Log_              Copilot_Licensed_              Copilot_Org_Data_
Direct_Ingester.ipynb           Users_Direct_Ingester.ipynb    Direct_Ingester.ipynb
        ↓                               ↓                               ↓
dbo.copilot_                    dbo.copilot_                   dbo.copilot_
interactions_parsed             licensed_users                 org_data
        └───────────────────────┴───────────────────────────┘
                                        ↓
                          PBIT (Sql.Database connector
                          + one direct Org→Licensed
                          relationship for filter context)
                                        ↓
                                Power BI Report
                                        ↑
                  + optional sources via their own ingester notebooks
                  (transcripts · credit consumption · product feedback · Agents 365)
```

The PBIT's two **required** parameters are **Fabric SQL Endpoint** and **Lakehouse Database**. Everything else is optional: a set of **`Enable_*` toggles** (`Enable_Dataverse`, `Enable_ProductFeedback`, `Enable_Agent365`, `Enable_Consumption`) switches the optional sources on or off, and each toggled-on source is populated by its own ingester notebook (see the table above). Optional sources you don't supply simply load **empty** — the core dashboard always works.

## Prerequisites

Before running the notebooks, you need:

1. **A Fabric workspace** assigned to a Fabric capacity (F2+ or trial), or Premium / PPU.
2. **A Lakehouse** in that workspace (any name; `CopilotAdoptionLake` is the convention used elsewhere in this repo).
3. **An Entra app registration** with these Microsoft Graph **application** permissions (admin consent required):
   - `AuditLog.Read.All` — for the audit log notebook
   - `Reports.Read.All` — for the licensed users notebook
   - `User.Read.All` — for the org data notebook
   Grab three values: **Tenant ID**, **Application (client) ID**, **Client secret value** (not Secret ID).

Helper scripts for app-registration setup live in [`archive/scripts/appreg/`](archive/scripts/appreg/) — they were written for the legacy flow but the resulting app registration works unchanged for the Direct Ingester notebooks.

## Quick start

### 1. Stand up the Lakehouse

- Open a Fabric workspace assigned to a Fabric capacity (F2+ or trial)
- **+ New → Lakehouse**, name it (e.g. `CopilotAdoptionLake`)
- Note the **SQL endpoint** under Lakehouse settings — looks like `<workspace-guid>.datawarehouse.fabric.microsoft.com`

### 2. Import and configure the three core Direct Ingester notebooks

For each of the three **core** notebooks under [`notebooks/`](notebooks/) (audit logs, licensed users, org data):

- In your Fabric workspace → **+ New → Import notebook** → upload the `.ipynb`
- Attach the notebook to your Lakehouse and **pin it as default** (📌 icon next to the name in the Lakehouses panel)
- Open **cell 2 (`# === CONFIG ===`)** and paste your three values:

  ```python
  TENANT_ID     = '<your-tenant-guid>'
  CLIENT_ID     = '<your-app-reg-client-id>'
  CLIENT_SECRET = '<your-client-secret-value>'
  ```

  > **For production**: replace the literal `CLIENT_SECRET = '...'` with a Key Vault read using `notebookutils.credentials.getSecret(...)`. Each notebook's CONFIG cell has a commented-out example.

### 3. Run all three notebooks

| Notebook | Run cadence | Output Delta table | Typical runtime |
|---|---|---|---|
| `Copilot_Audit_Log_Direct_Ingester.ipynb` | Daily — Graph caps audit-log queries to a 7-day window per request | `dbo.copilot_interactions_parsed` | 1–3 min depending on tenant size; the audit-log job is async (poll loop in the notebook) |
| `Copilot_Licensed_Users_Direct_Ingester.ipynb` | Weekly / monthly | `dbo.copilot_licensed_users` | Seconds |
| `Copilot_Org_Data_Direct_Ingester.ipynb` | Weekly | `dbo.copilot_org_data` | 30–90s for ~10K users (paginated) |

Use the **Schedule** button at the top of each notebook to set a cadence — or wire all three into a single **Fabric Pipeline**.

> **Optional sources** — to switch on the agent (Dataverse), product-feedback, credit-consumption, or Agents 365 pages, also import and run the relevant optional notebook from the table above (and, for export-only sources, optionally the matching flow in [`flows/`](flows/)). The plain-language [`CREDIT-CONSUMPTION-SETUP.md`](CREDIT-CONSUMPTION-SETUP.md) walks through the billing one end to end. Skip any you don't need — they load empty.

### 4. Connect the PBIT

- Open `AI-Business-Value-Dashboard-Fabric.pbit` in Power BI Desktop
- Supply the parameters when prompted:

| Parameter | Required? | Value |
|---|---|---|
| **Fabric SQL Endpoint** | ✅ | `<workspace-guid>.datawarehouse.fabric.microsoft.com` |
| **Lakehouse Database** | ✅ | `CopilotAdoptionLake` (or your chosen Lakehouse name) |
| **`Enable_Dataverse`** | Optional | `Include` to load the agent tables (transcript parser), else `Exclude` |
| **`Enable_ProductFeedback`** | Optional | `Include` to load `user_feedback`, else `Exclude` |
| **`Enable_Agent365`** | Optional | `Include` to load `agents_365`, else `Exclude` |
| **`Enable_Consumption`** | Optional | `Include` to load the 3 billing tables, else `Exclude` |

> **Optional sources load empty when off.** Set each `Enable_*` to `Exclude` for sources you don't supply and those pages stay dormant — no errors. **Agents 365** has two options: the supported **export lander** (`Copilot_Agent365_Lander.ipynb`), or the optional **registry-API preview** (`Copilot_Agent365_Registry_Ingester_PREVIEW.ipynb` — Frontier-program tenants only, delegated auth, can't run unattended). See [`../shared/docs/OPTIONAL-SOURCES.md`](../shared/docs/OPTIONAL-SOURCES.md).

- Click **Load**. Refresh should complete in seconds
- Publish to a Power BI workspace ideally **on the same Fabric capacity** so Direct Lake works without cross-capacity overhead

### 5. Schedule + secure the Service refresh

- Service → workspace → dataset Settings → **Data source credentials** → sign in to the SQL endpoint
- **Scheduled refresh** → enable, match the cadence to your notebook schedule

## Alternative platforms

The core artifacts in this folder (PBIT + the three Direct Ingester notebooks) are deliberately portable:

- **The notebooks** are plain Python + PySpark — they call Microsoft Graph via `requests` and write Delta with `df.write.saveAsTable(...)`. They run unchanged on any Spark engine (Fabric, Databricks, Synapse Spark) once two config lines are adjusted per environment.
- **The PBIT** uses the `Sql.Database()` connector, which works against any SQL endpoint that exposes the Delta/SQL tables — Fabric Lakehouse, Databricks SQL Warehouse, Synapse SQL pool, Azure SQL DB, Fabric Warehouse, on-prem SQL Server.

So the same set of files supports the deployments below; only a couple of paths/parameter values change.

### 🧱 Azure Databricks

The same three-notebook pattern applies. For each Direct Ingester, one config line changes per environment:

| Notebook | Adjust `OUTPUT_TABLE` from… |
|---|---|
| `Copilot_Audit_Log_Direct_Ingester.ipynb` | `'dbo.Copilot_Interactions_Parsed'` → e.g. `'main.copilot.interactions_parsed'` |
| `Copilot_Licensed_Users_Direct_Ingester.ipynb` | `'dbo.copilot_licensed_users'` → e.g. `'main.copilot.licensed_users'` |
| `Copilot_Org_Data_Direct_Ingester.ipynb` | `'dbo.copilot_org_data'` → e.g. `'main.copilot.org_data'` |

Schedule via **Databricks Workflows** instead of Fabric Pipelines (one job per notebook, or a single multi-task workflow).

**PBIT parameters:**

| Parameter | Value |
|---|---|
| **Fabric SQL Endpoint** | Your Databricks SQL Warehouse hostname (e.g. `<workspace-id>.cloud.databricks.com`) |
| **Lakehouse Database** | The Unity Catalog name (or `hive_metastore`) — the database the three Delta tables live in |

For a more polished native-connector experience, swap the M-query's `Sql.Database(...)` line for `Databricks.Catalogs(...)`. The rest of the M-query is unchanged. The PBIT expects the three tables (`copilot_interactions_parsed`, `copilot_licensed_users`, `copilot_org_data`) to all live in the same database — adjust the `Item=` literals in the M-queries if you split them across catalogs.

### 🔷 Azure Synapse / Azure SQL DB / Fabric Warehouse

- Run the Direct Ingester notebooks on a **Synapse Spark pool**, or replace each with an equivalent SQL stored procedure / dbt model that produces the same flat schema
- Land the output in any SQL table
- Use the PBIT's existing `Sql.Database(...)` connector — supply your hostname + database name in the two parameters

The PBIT only cares that the three tables (`dbo.copilot_interactions_parsed`, `dbo.copilot_licensed_users`, `dbo.copilot_org_data`) exist with their expected schemas — see [Schema reference](#schema-reference). If you rename any of them, adjust the corresponding `Item=` literal in the table's M-query.

### 🪣 Already pre-parsing CSVs upstream?

If you have an existing pipeline that produces parsed CSVs (matching the three Delta-table schemas below), the [`1. SharePoint/`](../1.%20SharePoint/) path can consume them directly without any Spark step.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `401 Unauthorized` from Graph in cell 2 | App reg secret expired or permissions not consented | Regenerate the secret in Entra; confirm admin consent is granted on all three Graph application permissions |
| `403 Forbidden` from `/auditLog/auditLogQueries` | App reg missing `AuditLog.Read.All` (Application, not Delegated) | Add the application permission, grant admin consent, regenerate token |
| Audit log query stays in `running` state forever | Tenant has a backlog of audit-log query jobs, or the date range is too wide | The notebook polls with backoff up to 30 min. If you hit the timeout, narrow `LOOKBACK_DAYS` in cell 2 |
| `Login failed` / `cannot open database` (PBI side) | SQL endpoint hostname or database name wrong | Re-check Lakehouse settings page for the exact SQL endpoint string |
| `the key didn't match any rows in the table` | A notebook ran against the wrong (non-default) Lakehouse, so the expected table name doesn't exist | In the notebook's Lakehouses panel, confirm your Lakehouse is **pinned** (📌) before re-running |
| All users show as "Unlicensed" / `Total Licensed Users` empty | Licensed users notebook hasn't been run yet, or its Graph response was empty | Check the notebook output for the `HasCopilot` flag derivation; widen the report period if needed (`REPORT_PERIOD = 'D30'`) |
| `Inactive Licensed Users` is 0 even with no filter | Every licensed user has audit activity (likely with synthetic / test data); or `UPN_Normalized` ↔ `PersonId_Normalized` casing mismatch | Run `SELECT COUNT(*) FROM dbo.copilot_licensed_users WHERE UPN_Normalized NOT IN (SELECT LOWER(LTRIM(RTRIM(Audit_UserId))) FROM dbo.copilot_interactions_parsed)` — if result is 0, your population is genuinely fully active |
| `Formula.Firewall` error (only on non-Fabric variants) | Cross-source merge with privacy levels mismatched | Service → dataset Settings → Data source credentials → set **Privacy: None** for both sources |
| Refresh slow (more than a minute) | Dataset is in Import mode | Switch the workspace to a Fabric capacity and convert to **Direct Lake** for sub-second response |
| Agents 365 data missing from the report | `Enable_Agent365` is `Exclude`, or the `agents_365` table hasn't been landed | Set `Enable_Agent365 = Include`; run `Copilot_Agent365_Lander.ipynb` (or the registry preview) to populate `agents_365`, then refresh |

## Schema reference

`dbo.copilot_interactions_parsed` has one row per **prompt × accessed-resource**. (Spark normalises `saveAsTable` names to lowercase, which is why the SQL endpoint exposes the table in lowercase even though the notebook variable uses `Copilot_Interactions_Parsed`.) Key columns:

| Column | Notes |
|---|---|
| `CreationDate` | Parsed from `AuditData.CreationTime` |
| `Audit_UserId` | The user's UPN (joined to the licensed-users + org tables) |
| `AppHost` | `Teams`, `Word`, `Excel`, `Copilot Studio`, etc. |
| `Workload` | Typically `Copilot` |
| `AISystemPlugin_Id` | `BingWebSearch` indicates Bing grounding was used |
| `AccessedResource_Type` | `WebSearchQuery`, `File`, `Email`, `EnterpriseSearch`, etc. |
| `Message_Id` / `Message_isPrompt` | One row per prompt; `Message_isPrompt = "TRUE"` always |
| `Resource_Count` | Original fan-out count |
| `InteractionDate` / `WeekStart` / `MonthStart` | Computed in PySpark |

For the full audit-log JSON schema see [Microsoft Learn — CopilotInteraction](https://learn.microsoft.com/en-us/office/office-365-management-api/copilot-schema).

## Customising the audit-log parser

The audit log notebook's `audit_schema` cell defines which JSON fields get extracted from `AuditData`. Add fields by extending that struct — the rest of the notebook adapts automatically as long as the new field is referenced in the `flat.select(...)` block.

For incremental refresh (only fetch new events since the last run), change `WRITE_MODE` to `'append'` and add a watermark filter on `CreationTime` keyed off the max value already in the Delta table. Then drop `LOOKBACK_DAYS` to 1–2 and run on a daily schedule.

## Migration from the legacy flow

If you were running the previous-generation PowerShell + Parser/Loader pipeline, see [`archive/README.md`](archive/README.md) for what changed and what to keep. The output schemas are identical, so the PBIT works either way.
