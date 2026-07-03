# Fabric + Copilot Studio — full setup (self-contained)

**Who this is for:** customers running Copilot **Studio** agents who want the full dashboard *including*
the Copilot Studio pages (agent transcripts, sessions, performance, and Studio message credits).

**One place, one path.** This guide is self-contained — every notebook and step you need is listed
below **in order**, so you don't have to jump between the main Fabric README and separate add-on docs.
It covers the three **core** sources *plus* the two **+ Copilot Studio** sources, then the template and
schedule. (If you *don't* use Copilot Studio, use the [main Fabric README](README.md) instead — you
don't need this.)

> All notebooks referenced below live in the shared [`notebooks/`](notebooks/) folder. This guide is
> the Studio-complete walkthrough; the [main README](README.md) is the core-only equivalent.

---

## What you'll end up with

```
                         Fabric Lakehouse (Delta tables)              Power BI
 Core     audit / licensed / org  →  copilot_interactions_parsed …  ┐
 Studio   Dataverse transcripts   →  agent_sessions / …_catalogue … ├→  Deeper Copilot Studio template
 Studio   PPAC message credits    →  credit_consumption_*           ┘
```

Five notebooks feed the Lakehouse; the **Deeper Copilot Studio Analysis** template reads it.

---

## Step 0 — Prerequisites

**Create a Lakehouse** in a Fabric workspace on a capacity (F2+ or trial): **+ New → Lakehouse**. Note
its **SQL endpoint** (`<workspace-guid>.datawarehouse.fabric.microsoft.com`) from Lakehouse settings.

**Register an Entra app** with these **Microsoft Graph application** permissions (admin-consented):

| Permission | Used by | Part |
|---|---|---|
| `AuditLogsQuery.Read.All` | Audit log notebook | Core |
| `Reports.Read.All` | Licensed users notebook | Core |
| `User.Read.All` | Org data notebook | Core |

**Extra access for the + Copilot Studio sources:**

| Source | Access needed |
|---|---|
| Dataverse agent transcripts | Dataverse **read** on `ConversationTranscript` (System Customizer / System Administrator / Environment Maker) in each Copilot Studio environment |
| PPAC Copilot Studio message credits | **Global Administrator** or **Billing Administrator** to export the `MCSMessages` reports from the Power Platform Admin Center (export-only, no API) |

Note the **Tenant ID**, **Client ID**, and a **Client secret value** for the notebook CONFIG cells.

---

## Step 1 — Core notebooks (required)

Import each into the workspace (**+ New → Import notebook**), attach + pin your Lakehouse as default,
paste your three values into the `# === CONFIG ===` cell, and run.

| # | Notebook | Cadence | Output table |
|---|---|---|---|
| 1 | [`notebooks/Copilot_Audit_Log_Direct_Ingester.ipynb`](notebooks/Copilot_Audit_Log_Direct_Ingester.ipynb) | Daily (Graph caps audit queries to 7 days) | `dbo.copilot_interactions_parsed` |
| 2 | [`notebooks/Copilot_Licensed_Users_Direct_Ingester.ipynb`](notebooks/Copilot_Licensed_Users_Direct_Ingester.ipynb) | Weekly / monthly | `dbo.copilot_licensed_users` |
| 3 | [`notebooks/Copilot_Org_Data_Direct_Ingester.ipynb`](notebooks/Copilot_Org_Data_Direct_Ingester.ipynb) | Weekly | `dbo.copilot_org_data` |

> For production, read the secret from Key Vault — each CONFIG cell has a commented
> `notebookutils.credentials.getSecret(...)` example.

---

## Step 2 — Copilot Studio notebooks (the add-on)

These two are what make it **Fabric + Copilot Studio**. Run both.

### 2a. Agent transcripts → Dataverse

[`notebooks/Copilot_Agent_Transcript_Parser.ipynb`](notebooks/Copilot_Agent_Transcript_Parser.ipynb)
pulls Copilot Studio conversation transcripts from **Dataverse** and builds the agent tables
(`agent_sessions`, `agent_turns`, `agent_errors`, `agent_subagents`, `agent_catalogue`,
`agent_performance`).

- Set `SOURCE_MODE = 'dataverse'` and list your environment URL(s) in the CONFIG cell.
- Or, for a one-off, export the `ConversationTranscript` table to CSV and point the notebook at
  `Files/` (see the manual-export note in the [main README](README.md)).

### 2b. Copilot Studio message credits → Power Platform Admin Center

[`notebooks/Copilot_Credit_Consumption_Ingester.ipynb`](notebooks/Copilot_Credit_Consumption_Ingester.ipynb)
builds the three billing tables (`credit_consumption_tenant/agent/user`) from the PPAC `MCSMessages`
exports. This is **export-only** — full walkthrough (including the auto-landing Power Automate flow) is
in [`CREDIT-CONSUMPTION-SETUP.md`](CREDIT-CONSUMPTION-SETUP.md).

Drop the three `EntitlementConsumption…MCSMessages…` CSVs into `Files/credit_consumption/`, then run
the notebook.

---

## Step 3 — Connect the template

Open **`AI Business Value Dashboard - 24-06-2026 - Deeper Copilot Studio Analysis.pbit`** (the
Studio-complete template — it has the extra Copilot Studio pages) in Power BI Desktop and set:

| Parameter | Value |
|---|---|
| **Fabric SQL Endpoint** | `<workspace-guid>.datawarehouse.fabric.microsoft.com` |
| **Lakehouse Name** | your Lakehouse name |
| `Enable_Dataverse` | `Include` — **+ Copilot Studio** |
| `Enable_AgentConsumption` | `Include` — **+ Copilot Studio** |
| `Enable_ProductFeedback` | `Include` / `Exclude` (optional) |
| `Enable_Agent365` | `Include` / `Exclude` (optional) |
| `Enable_CoworkConsumption` | `Include` / `Exclude` (optional) |

The **+ Copilot Studio** pair (`Enable_Dataverse` + `Enable_AgentConsumption`) is what lights up the
Copilot Studio pages — set both to `Include`. Click **Load**, then **Publish** (ideally to a workspace
on the **same Fabric capacity** for Direct Lake).

---

## Step 4 — Schedule the refresh

- **Notebooks:** use each notebook's **Schedule** button, or wire them into one Fabric pipeline (see
  [`pipelines/`](pipelines/)). Match cadence to Step 1/2 (audit daily; the rest weekly/monthly).
- **Dataset:** in the Service, dataset **Settings → Data source credentials** → sign in to the SQL
  endpoint, then enable **Scheduled refresh**.

---

## Reference

- **Optional-source pattern & toggles:** [`docs/OPTIONAL-SOURCES.md`](docs/OPTIONAL-SOURCES.md)
- **Credit consumption, step by step:** [`CREDIT-CONSUMPTION-SETUP.md`](CREDIT-CONSUMPTION-SETUP.md)
- **Table schemas:** [`docs/DATA-DICTIONARY.md`](docs/DATA-DICTIONARY.md)
- **Roles & permissions (all sources):** [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md)
- **Core-only setup (no Copilot Studio):** [`README.md`](README.md)
