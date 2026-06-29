# AI Business Value Dashboard — Dataverse template

**A self-contained Power BI template that runs straight off Dataverse + a couple of CSV file paths.
No Fabric capacity, no Lakehouse, no notebooks, no Spark.**

Point it at your Dataverse environment, give it a folder of supporting CSVs, and refresh. The
Copilot Studio conversation transcripts are parsed **inside the Power BI model in Power Query (M)**,
so the dashboard does its own crunching — there is nothing else to stand up or run.

```
Dataverse  conversationtranscripts ─(native connector, Web API)─┐
                                                                 ▼
                        Power Query M parser (in the model)
                                                                 ▼
   Agent Sessions · Agent Turns · Agent Errors · Sub-Agent Calls
   Agent Performance · Agent Catalogue · Knowledge Citations
                                                                 ▼
   + org / Agents 365  ─(direct CSV file paths)──────────────────────► dashboard
```

> **Just want the file?** Open
> **[`AI Business Value Dashboard - Dataverse.pbit`](./AI%20Business%20Value%20Dashboard%20-%20Dataverse.pbit)**
> in Power BI Desktop and fill in the parameters below.

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

**Supporting CSV files**, each pointed to by its own **full file path** parameter (a SharePoint
file URL or a local / synced / UNC path):

| File | Source export | Parameter | Required? |
|---|---|---|---|
| `copilot_org_data.csv` | Entra → Users (manual export) **or** the Graph `/users` → SharePoint landing flow | **Org Data CSV** | **Yes** (org filter on every page) |
| `agents_365.csv` | M365 Admin → Agents → **Export** | **Agent 365 CSV** | optional — leave blank to skip |

Org data is read straight from the **raw portal export** — the model normalises the headers and
US-format dates for you, so just point the parameter at the file. The Agents 365 file is optional;
leave its parameter blank and that table simply loads empty (its visuals degrade gracefully).

> **Credit Consumption is not part of this template.** This Dataverse build is deliberately scoped
> to **Copilot Studio** analytics (transcripts + org + optional Agents 365). If you need the Power
> Platform credit-consumption / billing page, use the **Fabric** or **SharePoint** template.

### How the file paths work

Each CSV parameter takes a **full file path**, auto-detected:

| You enter | Connector used | Refresh in the Service |
|---|---|---|
| A **SharePoint file URL** (`https://contoso.sharepoint.com/sites/AICopilot/Shared Documents/copilot_org_data.csv`) | `Web.Contents` | ✅ cloud-to-cloud, **no gateway** (set the source to *Organizational account* / OAuth2) |
| A **local or synced file** (`C:\AIBV\copilot_org_data.csv`, or a synced `…\OneDrive - Contoso\copilot_org_data.csv`) | `File.Contents` | needs an **on-premises data gateway** |
| A **UNC path** (`\\server\share\copilot_org_data.csv`) | `File.Contents` | needs a gateway |

> Tip: a **SharePoint file URL is the easiest to schedule-refresh** — no gateway. Pointing at the
> exact file (rather than a folder) means the report doesn't depend on file-naming conventions and
> won't silently miss a renamed export.

> **Org data — keep your existing options.** Org/people data is **not** read from Dataverse; it
> stays a CSV so you keep both acquisition methods: the **manual Entra export**, or an
> **Entra-Graph-API → SharePoint** landing flow. The dashboard just reads the resulting
> `copilot_org_data.csv` at the path you give it.

---

## Connect the template

Open the `.pbit` in Power BI Desktop. It is **pre-set to Dataverse** — you only set these
parameters (no Fabric, Lakehouse, or mode switches to worry about):

| Parameter | Required? | Value |
|---|---|---|
| **Dataverse Url** | **Yes** | your environment URL, e.g. `https://yourorg.crm.dynamics.com` |
| **Org Data CSV** | **Yes** | full file path (SharePoint URL or local/synced/UNC) to `copilot_org_data.csv` |
| **Agent 365 CSV** | optional | full file path to `agents_365.csv` — **leave blank to skip** the Agents 365 table |

Click **Load**. On first refresh you'll get a one-time **Dataverse** sign-in: choose
**Organizational account**, sign in with the org login that can read the Conversation Transcript
table, and (if prompted) set the source privacy level to **Organizational**. Each CSV path, if
local, uses your current Windows credentials; if it's a SharePoint URL, sign in with
**Organizational account** there too. Then enable **Scheduled refresh** in the Service as usual.

---

## How the transcript parser works

The model carries a set of Power Query functions (see
[`model_expressions_reference.tmdl`](./model_expressions_reference.tmdl)) that parse the raw
`conversationtranscripts` JSON into the dashboard's fact tables — entirely in the model, with no
external compute:

| M function | Produces |
|---|---|
| `RawTranscripts()` | one row per transcript: `conversationtranscriptid, content, …` (live from Dataverse) |
| `ParsedBase()` | parses each `content` JSON once into an `activities` list |
| `Parse_Sessions()` | `Agent Sessions` (one row per conversation) |
| `Parse_Turns()` | `Agent Turns` (one row per message, with intent / knowledge / feedback) |
| `Parse_Errors()` | `Agent Errors` |
| `Parse_SubAgents()` | `Agent Sub-Agent Calls` |
| `Parse_Performance()` | `Agent Performance` (per-conversation KPI fact) |

`Agent Catalogue` self-derives from the parsed sessions + sub-agents.

**Notes / limitations**
- **Topics** are classified by the model's generic, customer-agnostic topic logic (DAX) — so topics
  work with no extra services or LLM enrichment.
- **Agent name** for single-agent transcripts is resolved via the Dataverse bot lookup when the
  environment exposes it; where it doesn't, the agent is still resolved from the transcript content.
- Token / plugin telemetry columns are null in this path (not present in the transcript JSON); the
  value model doesn't depend on them.
- Conversation transcripts default to ~30-day retention in Dataverse — the dashboard only sees what
  the environment currently holds.

---

## Verifying the connection

A built-in **`Dataverse Diagnostic`** table returns the live row count of `conversationtranscripts`
and `systemusers`, so you can confirm the connector works and whether the environment actually has
transcripts yet. If `conversationtranscripts = 0` but `systemusers > 0`, the connection is fine —
the environment simply has no Copilot Studio transcripts in scope yet.

---

## How this relates to the other templates

This is one of three deployment templates in the repo, each self-contained — pick the one that
fits your platform:

| Template | Best for | Needs |
|---|---|---|
| [`1. Fabric`](../1.%20Fabric) | large tenants, scheduled Spark ingestion | Fabric capacity + Lakehouse |
| [`2. SharePoint`](../2.%20SharePoint) | flat-file / Power Automate landing | a SharePoint library |
| **`3. Dataverse`** *(this one)* | **simplest footprint** | a Dataverse env + a CSV folder |
