# Copilot Cost Consumption — Cowork / WorkIQ / Other credits

This source brings in the **per-user Cowork / WorkIQ / Other credit split** that the Power Platform
message-consumption exports (`credit_consumption_*`) do **not** contain. It is **additive** to those
billing tables — the two answer different questions (per-agent Copilot Studio *message* credits vs
per-user *surface* credits).

```
                       ┌─ Email arrives with CSV ─┐
M365 Admin Center ─────┤                          ├─▶ OneLake  Files/cost_consumption/*.csv ─▶ Cost Consumption Ingester ─▶ Delta
 (Cost management)     └─ Dropped to SharePoint ──┘
```

## Where to get the export

**Microsoft 365 Admin Center → Copilot → Cost management → Consumption tab → Export CSV.**
It is **export-only — there is no API**. The per-user rows carry `User Principal Name`,
`Cowork Credits`, `WorkIQ Credits`, `Other Credits`, and `Last Activity Date`.

## The two landing flows

| File | When to use |
| --- | --- |
| `Copilot_CostConsumption_Email_to_OneLake.json` | The export arrives by **email** (mailed, or a scheduled export is mailed). Subject filter default `Copilot Cost Management`. |
| `Copilot_CostConsumption_SharePoint_to_OneLake.json` | The customer prefers a **governed SharePoint document library** drop folder. |

Both write to OneLake with the **DFS (ADLS Gen2) three-step pattern** (`PUT ?resource=file` →
`PATCH ?action=append` → `PATCH ?action=flush`), audience `https://storage.azure.com/`, landing in
**`Files/cost_consumption/`** (must match `SOURCE_DIR` in `../notebooks/Copilot_Cost_Consumption_Ingester.ipynb`).
The MAC export filename is not fixed, so the `FileNamePrefix` guard defaults to empty (accept any
`.csv`); set it once you know the real prefix to be stricter. Import & OneLake-permission steps are
identical to the credit-consumption flows — see [`README.md`](./README.md).

## Column contract (the CSV)

One row per user. Source header → sanitised Delta/column name (sanitiser = any run of
`[ ,;{}()\n\t=/-]` → `_`, BOM stripped, **case preserved**):

| Source header | Sanitised name | Type | Notes |
|---|---|---|---|
| `User Principal Name` | `User_Principal_Name` | text | **Join key** (→ org `PersonId` / UPN) |
| `Cowork Credits` | `Cowork_Credits` | double | blank → null |
| `WorkIQ Credits` | `WorkIQ_Credits` | double | blank → null |
| `Other Credits` | `Other_Credits` | double | blank → null |
| `Last Activity Date` | `Last_Activity_Date` | date | parses en-US `M/d/yyyy` + ISO |

**Added by the ingester:** `Total_Credits` (= Cowork + WorkIQ + Other, nulls→0), plus `SourceFile`
and `LoadDate` lineage. The model binds **by name** — these names must match exactly.

## Model wiring

- **Toggle:** `Enable_CostConsumption` (list parameter `"Include"` / `"Exclude"`, default `"Include"`).
- **Table:** `copilot_cost_consumption`, wrapped in the standard `EmptyTable` + `try…otherwise` pattern
  (Fabric reads the Delta table via `FabricTable`; SharePoint reads the `Cost Consumption File` CSV and
  does the light typing + `Total_Credits` in M).
- **Relationships:** `User_Principal_Name` → `Chat + Agent Org Data[PersonId]` (department / chargeback
  attribution for free); `Last_Activity_Date` → `Calendar[Date]`.
- **Grain:** per-user **snapshot** — `Last_Activity_Date` is "last activity", not a daily credit series.
  Treat like the existing credit tables (snapshot cards + billing-period label), not a daily trend.

## Not all customers will send this

That's expected. If `Files/cost_consumption/` is empty (or the toggle is `"Exclude"`), the ingester
writes an **empty, correctly-named** table and the Cost Consumption visuals stay dormant — the rest of
the dashboard is unaffected.

> The optional-source toggles are **list parameters** with the values `"Include"` / `"Exclude"`
> (not `true`/`false`). Set `Enable_CostConsumption` to `"Include"` once the data is landing.

## UPN attribution caveat

The UPN match against org data isn't guaranteed 100%. Users in the cost export with no matching org
row won't attribute to a department — surface them under an **"(Unattributed)"** bucket and show the
match rate, so a gap is visible rather than silently dropped.
