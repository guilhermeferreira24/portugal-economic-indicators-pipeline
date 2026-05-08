# Portugal Economic Indicators Pipeline

## Overview

This project builds an end-to-end data pipeline that extracts real economic indicators from the **Banco de Portugal BPstat API** — inflation, interest rates, credit volume, non-performing loans, unemployment and GDP — processes them in Python, loads them into Google BigQuery, analyses them with SQL, and visualises the results in Power BI.

All data is sourced directly from official Banco de Portugal endpoints, covering the period from 2010 to 2025, and the pipeline can be re-run at any time to refresh the dataset with the latest available figures.

***

## Objective

- Extract 8 official economic series from the BPstat API using Python
- Transform and enrich the data with derived metrics (YoY variation, spread, economic period classification)
- Load structured tables into Google BigQuery for analysis
- Analyse monetary policy, credit risk, and inflation trends using 10 progressive SQL queries
- Build a 3-page interactive Power BI dashboard connected directly to BigQuery

***

## Dataset

| Series | Indicator | Frequency | Period | BigQuery Table |
|--------|-----------|-----------|--------|----------------|
| Inflation | IHPC — Harmonised Index of Consumer Prices Portugal | Monthly | 2010–2025 | `portugal_economic_indicators.inflation_rates` |
| Rates | Euribor 3M — interbank market reference rate | Monthly | 2010–2025 | `portugal_economic_indicators.inflation_rates` |
| Rates | Euribor 12M — mortgage credit reference rate | Monthly | 2010–2025 | `portugal_economic_indicators.inflation_rates` |
| Credit | Average interest rate — housing loans to households | Monthly | 2010–2025 | `portugal_economic_indicators.inflation_rates` |
| Credit | Total credit volume to households | Monthly | 2010–2025 | `portugal_economic_indicators.credit_macro` |
| Credit | Non-Performing Loans ratio (NPL) | Quarterly | 2010–2025 | `portugal_economic_indicators.credit_macro` |
| Macro | Unemployment rate Portugal | Quarterly | 2010–2025 | `portugal_economic_indicators.credit_macro` |
| Macro | GDP — real annual growth | Annual | 2010–2025 | `portugal_economic_indicators.credit_macro` |

### Schema

| Column | Type | Description |
|--------|------|-------------|
| `data` | DATE | Observation date |
| `valor` | FLOAT | Indicator value |
| `indicador` | STRING | Series name (IHPC, Euribor_3M, NPL…) |
| `ano` | INTEGER | Extracted year |
| `mes` | INTEGER | Extracted month |
| `periodo` | STRING | Economic period classification (Crise / Recuperacao / COVID / Expansao) |

***

## Tools & Stack

- **Python (requests + Pandas)** — API extraction, data cleaning and transformation (Google Colab)
- **Google BigQuery** — SQL analysis (CTEs, Window Functions, LAG, DENSE_RANK, PERCENTILE)
- **pandas-gbq** — direct load from Colab DataFrames into BigQuery tables
- **Power BI** — 3-page interactive dashboard connected natively to BigQuery
- **GitHub** — version control and portfolio

***

## Key Terms

| Term | Description |
|------|-------------|
| **IHPC** | Harmonised Index of Consumer Prices — the standard EU inflation measure used by the ECB to set monetary policy targets |
| **Euribor** | Euro Interbank Offered Rate — the reference rate at which European banks lend to each other; drives mortgage rates across the Eurozone |
| **Spread** | Difference between the housing loan rate and Euribor 12M — measures how much margin banks add above the reference rate |
| **NPL** | Non-Performing Loans — credit where the borrower has stopped making payments; a direct measure of credit risk in the banking sector |
| **YoY** | Year-over-Year — compares a value to the same month in the previous year, removing seasonal noise |
| **Taxa Real** | Real interest rate — Euribor minus inflation; when negative, saving money loses real purchasing power |
| **BPstat API** | Banco de Portugal's public data API — provides official time series for all Portuguese macroeconomic indicators |
| **ECB Target** | The European Central Bank's inflation target is 2% — used in this project as a threshold for above-target months |

***

## Approach

The project was divided into three stages:

**Stage 1 — Python Pipeline (Google Colab)**
Extract 8 economic series from the BPstat API via CSV endpoint, clean and normalise each series, engineer derived metrics (YoY variation, spread, economic period), and load the structured tables into BigQuery using `pandas-gbq`.

**Stage 2 — SQL Analysis (BigQuery)**
10 queries across three complexity levels: basic aggregation and filtering, temporal analysis with window functions, and advanced CTEs with DENSE_RANK, LAG, and PERCENTILE functions.

**Stage 3 — Power BI Dashboard**
3-page interactive dashboard built on top of the BigQuery tables, connected via the native Power BI → BigQuery connector, with DAX measures for dynamic KPIs.

***

## Stage 1 — Python Pipeline

```python
import pandas as pd
import requests
from io import StringIO

SERIES = {
    "IHPC":           "5739164",
    "Euribor_3M":     "13168436",
    "Euribor_12M":    "13168437",
    "Taxa_habitacao": "12519808",
    "Volume_credito": "12519806",
    "NPL":            "12519807",
    "Desemprego":     "12518324",
    "PIB":            "12518325",
}

BASE_CSV_URL = "https://bpstat.bportugal.pt/api/observations/csv/?series_ids={}&language=PT"

def extract_series_csv(series_id, nome):
    url = BASE_CSV_URL.format(series_id)
    r = requests.get(url, timeout=30)
    r.raise_for_status()

    df = pd.read_csv(StringIO(r.text), sep=";")

    if df.empty:
        return pd.DataFrame(columns=["data", "valor", "indicador"])

    col_map = {}
    for c in df.columns:
        cl = c.strip().lower()
        if "período" in cl or "periodo" in cl:
            col_map[c] = "data"
        elif cl == "valor":
            col_map[c] = "valor"

    df = df.rename(columns=col_map)

    if "data" not in df.columns or "valor" not in df.columns:
        return pd.DataFrame(columns=["data", "valor", "indicador"])

    df["data"]     = pd.to_datetime(df["data"], errors="coerce")
    df["valor"]    = pd.to_numeric(df["valor"], errors="coerce")
    df["indicador"] = nome

    return df[["data", "valor", "indicador"]].dropna(subset=["data", "valor"])

# Extract all 8 series
print("Extracting 8 BPstat series...")
dfs = []
for nome, sid in SERIES.items():
    d = extract_series_csv(sid, nome)
    if len(d) > 0:
        print(f"  ✅ {nome} → {len(d)} rows")
        dfs.append(d)
    else:
        print(f"  ❌ NO DATA: {nome}")

df_master = pd.concat(dfs, ignore_index=True)
df_master = df_master.sort_values(["indicador", "data"]).reset_index(drop=True)
```

The BPstat API returns semicolon-separated CSV files with Portuguese column headers. The extraction function normalises column names dynamically — detecting the date column regardless of accent variations in the header (`período` vs `periodo`) — before parsing types and tagging each row with its series name.

***

### Transform

```python
# Derive year, month and economic period
df_master["ano"]  = df_master["data"].dt.year
df_master["mes"]  = df_master["data"].dt.month
df_master["periodo"] = pd.cut(
    df_master["ano"],
    bins=[2009, 2014, 2019, 2021, 2025],
    labels=["Crise", "Recuperacao", "COVID", "Expansao"]
)

# Filter to 2010–2025
df_master = df_master[
    (df_master["ano"] >= 2010) & (df_master["ano"] <= 2025)
].reset_index(drop=True)

df_master.to_csv("pipeline_completo.csv", index=False)
print(f"✅ Pipeline complete — {len(df_master)} rows across {df_master['indicador'].nunique()} series")
```

The economic period classification uses `pd.cut()` to bin years into four labelled eras: **Crise** (2010–2014), **Recuperacao** (2015–2019), **COVID** (2020–2021), and **Expansao** (2022–2025). This column is carried into BigQuery and used directly as a slicer dimension in Power BI.

***

### Load

```python
from google.colab import auth
import pandas_gbq

auth.authenticate_user()

PROJECT_ID = "your-project-id"
DATASET    = "portugal_economic_indicators"

pandas_gbq.to_gbq(
    df_inflation,
    f"{DATASET}.inflation_rates",
    project_id=PROJECT_ID,
    if_exists="replace"
)

pandas_gbq.to_gbq(
    df_credit_macro,
    f"{DATASET}.credit_macro",
    project_id=PROJECT_ID,
    if_exists="replace"
)

print("✅ Pipeline complete — BigQuery updated")
```

`if_exists="replace"` ensures the table is fully refreshed on each pipeline run — no duplicate rows accumulate across executions.

***

## Stage 2 — SQL Analysis (BigQuery)

All queries were run on Google BigQuery Sandbox (free tier) against the dataset `portugal_economic_indicators`.

### Basic Exploration

**Query 1 — Average Inflation by Year and Economic Period**

```sql
SELECT
  ano,
  mes,
  periodo,
  AVG(valor) AS inflacao_media_pct
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador = 'IHPC'
GROUP BY ano, mes, periodo
ORDER BY ano, mes;
```

***

**Query 2 — Months Where Inflation Exceeded 3% (ECB Target)**

```sql
SELECT
  ano,
  periodo,
  COUNT(*) AS meses_acima_3pct
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador = 'IHPC'
  AND valor > 3
GROUP BY ano, periodo
ORDER BY ano;
```

***

**Query 3 — Euribor 3M vs 12M Evolution by Year**

```sql
SELECT
  ano,
  AVG(CASE WHEN indicador = 'Euribor_3M'  THEN valor END) AS euribor_3m_media,
  AVG(CASE WHEN indicador = 'Euribor_12M' THEN valor END) AS euribor_12m_media
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador IN ('Euribor_3M', 'Euribor_12M')
GROUP BY ano
ORDER BY ano;
```

Pivoting two series in a single query using conditional `AVG(CASE WHEN)` avoids a JOIN and returns both rates side by side per year — clean for direct use in Power BI line charts.

***

### Temporal Analysis

**Query 4 — Housing Loan Spread vs Euribor 12M**

```sql
SELECT
  ano,
  AVG(CASE WHEN indicador = 'Taxa_habitacao' THEN valor END) AS taxa_habitacao_media,
  AVG(CASE WHEN indicador = 'Euribor_12M'    THEN valor END) AS euribor_12m_media,
  AVG(CASE WHEN indicador = 'Taxa_habitacao' THEN valor END) -
  AVG(CASE WHEN indicador = 'Euribor_12M'    THEN valor END) AS spread_medio
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador IN ('Taxa_habitacao', 'Euribor_12M')
GROUP BY ano
ORDER BY ano;
```

The `spread_medio` column measures how much margin banks charged above the reference rate each year — the core metric behind one of the project's key findings.

***

**Query 5 — YoY Inflation Variation with LAG()**

```sql
WITH ihpc AS (
  SELECT data, ano, mes, periodo, valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
)
SELECT
  data, ano, mes, periodo, inflacao,
  LAG(inflacao, 12) OVER (ORDER BY data)                          AS inflacao_12m_antes,
  ROUND((inflacao - LAG(inflacao, 12) OVER (ORDER BY data)), 2)   AS variacao_yoy
FROM ihpc
ORDER BY data;
```

`LAG(inflacao, 12)` looks back exactly 12 rows in the time-ordered partition — equivalent to the same month in the prior year — computing a true YoY delta without any calendar join.

***

**Query 6 — 12-Month Moving Average of Inflation**

```sql
WITH ihpc AS (
  SELECT data, ano, mes, periodo, valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
)
SELECT
  data, ano, mes, periodo, inflacao,
  AVG(inflacao) OVER (
    ORDER BY data
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
  ) AS media_movel_12m
FROM ihpc
ORDER BY data;
```

`ROWS BETWEEN 11 PRECEDING AND CURRENT ROW` creates a rolling 12-month window that smooths out short-term spikes and reveals the true underlying inflation trend.

***

### Advanced — Window Functions & CTEs

**Query 7 — Top 5 Inflation Months per Economic Period (DENSE_RANK)**

```sql
WITH ihpc AS (
  SELECT data, ano, mes, periodo, valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
),
ranked AS (
  SELECT
    data, ano, mes, periodo, inflacao,
    DENSE_RANK() OVER (
      PARTITION BY periodo
      ORDER BY inflacao DESC
    ) AS rank_in_periodo
  FROM ihpc
)
SELECT data, ano, mes, periodo, inflacao, rank_in_periodo
FROM ranked
WHERE rank_in_periodo <= 5
ORDER BY periodo, rank_in_periodo, data;
```

`DENSE_RANK()` is used instead of `RANK()` to avoid gaps when tied values exist — ensuring every period always produces exactly 5 results regardless of ties.

***

**Query 8 — Euribor vs NPL Correlation (Quarterly CTE)**

```sql
WITH euribor AS (
  SELECT
    DATE_TRUNC(data, QUARTER) AS trimestre,
    AVG(CASE WHEN indicador = 'Euribor_3M' THEN valor END) AS euribor_3m_media
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'Euribor_3M'
  GROUP BY trimestre
),
npl AS (
  SELECT
    DATE_TRUNC(data, QUARTER) AS trimestre,
    AVG(valor)                AS npl_media
  FROM `portugal_economic_indicators.credit_macro`
  WHERE indicador = 'NPL'
  GROUP BY trimestre
)
SELECT
  e.trimestre,
  e.euribor_3m_media,
  n.npl_media
FROM euribor e
JOIN npl n ON e.trimestre = n.trimestre
ORDER BY e.trimestre;
```

`DATE_TRUNC(..., QUARTER)` aligns the monthly Euribor series with the quarterly NPL series before joining — without this normalisation the JOIN would return no matches due to date granularity mismatch.

***

**Query 9 — Months of Negative Real Rate (Inflation > Euribor)**

```sql
WITH inflacao AS (
  SELECT data, valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
),
euribor AS (
  SELECT data, valor AS euribor_3m
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'Euribor_3M'
)
SELECT
  i.data,
  i.inflacao,
  e.euribor_3m,
  (e.euribor_3m - i.inflacao) AS taxa_real
FROM inflacao i
JOIN euribor e ON i.data = e.data
WHERE (e.euribor_3m - i.inflacao) < 0
ORDER BY i.data;
```

Returns every month where the real rate was negative — the period where saving money actively lost purchasing power. This result feeds directly into the KPI card on Page 3 of the dashboard.

***

**Query 10 — Inflation Percentile by Decade (2010s vs 2020s)**

```sql
WITH ihpc AS (
  SELECT
    ano,
    CASE
      WHEN ano BETWEEN 2010 AND 2019 THEN '2010s'
      WHEN ano BETWEEN 2020 AND 2029 THEN '2020s'
    END AS decada,
    valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
    AND ano BETWEEN 2010 AND 2025
)
SELECT
  decada,
  APPROX_QUANTILES(inflacao, 2)[OFFSET(1)]  AS mediana_inflacao,
  APPROX_QUANTILES(inflacao, 10)[OFFSET(9)] AS p90_inflacao
FROM ihpc
GROUP BY decada
ORDER BY decada;
```

`APPROX_QUANTILES` computes the median (`[OFFSET(1)]` of a 2-quantile split) and the 90th percentile (`[OFFSET(9)]` of a 10-quantile split) — comparing the full distribution of inflation between decades rather than just comparing averages.
