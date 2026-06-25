# Dataverse deployment (no Fabric, no Spark)

Run the AI Business Value Dashboard **straight off Dataverse + a handful of CSV exports** —
no Fabric capacity, no Lakehouse, no notebooks. The conversation transcripts are parsed
**inside the Power BI model in Power Query (M)**, so the same JSON the Spark parser used to
crunch is now handled by the dashboard itself.

```
Dataverse  conversationtranscripts ─(native connector, Web API)─┐
                                                                 ▼
                        Power Query M parser (in the model)
                                                                 ▼
   Agent Sessions · Agent Turns · Agent Errors · Sub-Agent Calls
   Agent Performance · Agent Catalogue · Knowledge Citations
                                                                 ▼
   + org / credit / Agents 365  ─(CSV exports in a folder)─────────► dashboard
```

This is the third supported path alongside [`1. Fabric`](../1.%20Fabric) (recommended for large
tenants) and [`2. SharePoint`](../2.%20SharePoint). Pick Dataverse when you want the **simplest
footprint**: one connector, a folder of CSVs, and the report's own refresh — nothing else to run.

---

## What you need

**In your tenant**
- The **Dataverse environment URL** that holds the Copilot Studio transcripts
  (Power Platform Admin Center → Environments → *your env* → **Environment URL**,
  e.g. `https://yourorg.crm.dynamics.com`).
- A sign-in (the person who refreshes the report) with **Read** on the **Conversation
  Transcript** table in that environment — e.g. *System Administrator*, *System Customizer*,
  *Environment Maker*, or a custom least-privilege role. **No app registration / client secret**
  is needed — the report uses the native Dataverse connector with the refresher's own org login.

**A folder of CSV exports** (local path or a synced SharePoint/OneDrive folder), holding the
supporting sources by these **canonical file names**:

| File name | Source export | Used by |
|---|---|---|
| `copilot_org_data.csv` | Entra → Users (manual export) **or** the Graph `/users` → SharePoint landing flow | Org filter on every page |
| `credit_consumption_agent.csv` | Power Platform Admin → Billing → `EntitlementConsumption…PerAgentDetailsReport…` | Credit Consumption |
| `credit_consumption_user.csv` | `EntitlementConsumption…PerUserDetailsReport…` | Credit Consumption |
| `credit_consumption_tenant.csv` | `EntitlementConsumption…TenantDetailsReport…` | Credit Consumption |
| `agents_365.csv` | M365 Admin → Agents → **Export** (optional) | Agents 365 page |

Org data and credit are read straight from the **raw portal exports** — the model normalises the
headers for you, so just drop the files in and rename them to the canonical names above. Any file
that's absent simply loads empty (its page degrades gracefully); only `copilot_org_data.csv` is
needed for the org filter.

### Where the CSV folder can live

**CSV Folder Path** auto-detects what you give it:

| You enter | Connector used | Refresh in the Service |
|---|---|---|
| A **SharePoint site URL** (`https://contoso.sharepoint.com/sites/AICopilot`) | `SharePoint.Files` — finds the canonical file names anywhere in the site | ✅ cloud-to-cloud, **no gateway** (set the source to *Organizational account* / OAuth2) |
| A **local or synced folder** (`C:\AIBV\exports`, or a synced `…\OneDrive - Contoso\exports`) | `File.Contents` | needs an **on-premises data gateway** |
| A **UNC share** (`\\server\share\exports`) | `File.Contents` | needs a gateway |

> Tip: a **SharePoint site URL is the easiest to schedule-refresh** — no gateway. Drop the five
> canonical CSVs into any document library on that site. (The path is taken from the parameter
> directly, so the Service doesn't flag a dynamic data source.)

> **Org data — keep your existing options.** Org/people data is **not** read from Dataverse; it
> stays a CSV so you keep both acquisition methods: the **manual Entra export**, or the existing
> **Entra-Graph-API → SharePoint** landing flow (see [`1. Fabric/flows`](../1.%20Fabric/flows)).
> The dashboard just reads the resulting `copilot_org_data.csv`.

---

## Connect the template

Open the `.pbit` in Power BI Desktop. It is **pre-set to Dataverse** (Source Mode is fixed),
so you only set these parameters:

| Parameter | Required? | Value |
|---|---|---|
| **Dataverse Url** | **Yes** | your environment URL, e.g. `https://yourorg.crm.dynamics.com` |
| **CSV Folder Path** | **Yes** | a **SharePoint site URL** (`https://contoso.sharepoint.com/sites/AICopilot`) **or** a local/synced/UNC folder holding the CSV exports above (the **org/people** file lives here) |
| **Enable_Consumption** | optional | `Include` to load the credit-consumption CSVs / page (else `Exclude`) |
| **Enable_Agent365** | optional | `Include` to load the Agents 365 CSV / page (else `Exclude`) |

> The template carries **no** Fabric / Lakehouse / Source-Mode parameters — it's the Dataverse
> path only. (The multi-path master `.pbit` in `1. Fabric` keeps those if you need them.)

Click **Load**. On first refresh you'll get a one-time **Dataverse** sign-in: choose
**Organizational account**, sign in, and (if prompted) set the source privacy level to
**Organizational**. Then enable **Scheduled refresh** in the Service as usual.

---

## How the transcript parser works

The model carries a set of Power Query functions (see
[`model_expressions_reference.tmdl`](./model_expressions_reference.tmdl)) that mirror the Fabric
notebook's `build_*` steps exactly:

| M function | Notebook equivalent | Produces |
|---|---|---|
| `RawTranscripts()` | cells 2a/2b (ingest) | one row per transcript: `conversationtranscriptid, content, …` |
| `ParsedBase()` | `get_activities` | parses the `content` JSON once into an `activities` list |
| `Parse_Sessions()` | `build_sessions` | `Agent Sessions` (one row per conversation) |
| `Parse_Turns()` | `build_turns` | `Agent Turns` (one row per message, with intent/knowledge/feedback) |
| `Parse_Errors()` | `build_errors` | `Agent Errors` |
| `Parse_SubAgents()` | `build_subagents` | `Agent Sub-Agent Calls` |
| `Parse_Performance()` | `build_agent_performance` | `Agent Performance` (per-conversation KPI fact) |

Each fact table's source switches on **Source Mode**: `if Source Mode <> "Fabric" then Parse_X()
else <Lakehouse table>`. `Agent Catalogue` self-derives from the parsed sessions + sub-agents.

**Notes / limitations**
- **Topics** are classified by the model's generic, customer-agnostic topic logic (DAX), not the
  notebook's optional LLM enrichment — so topics work with no extra services.
- **Agent name** for single-agent transcripts is resolved via the Dataverse bot lookup
  (`bot_conversationtranscriptid($select=schemaname)`), which only the live `Dataverse` mode carries;
  in `TranscriptCSV` mode multi-agent transcripts still resolve their agent from the content.
- A `conversationtranscripts.csv` **exported via Excel** truncates the `content` cell at ~32,767
  chars and corrupts long transcripts — export to CSV directly (or use `Dataverse` mode) to avoid it.
- Token/plugin telemetry columns are null in this path (not present in the transcript JSON); the
  value model doesn't depend on them.

---

## Verifying the connection

A built-in **`Dataverse Diagnostic`** table (visible in `Dataverse` mode) returns the live row
count of `conversationtranscripts` and `systemusers`, so you can confirm the connector works and
whether the environment actually has transcripts yet. If `conversationtranscripts = 0` but
`systemusers > 0`, the connection is fine — the environment just has no Copilot Studio transcripts
in scope yet (they default to ~30-day retention).
