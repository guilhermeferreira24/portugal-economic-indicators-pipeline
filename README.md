# End-to-End Economic Data Pipeline · Portugal 2010–2025

![Banner](https://github.com/guilhermeferreira24/portugal-economic-indicators-pipeline/blob/main/newbanner.png?raw=true)

![Python](https://img.shields.io/badge/Python-3.10-blue)
![BigQuery](https://img.shields.io/badge/Google-BigQuery-orange)
![PowerBI](https://img.shields.io/badge/Power-BI-yellow)
![Status](https://img.shields.io/badge/Status-Complete-brightgreen)

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
| Inflation | HICP — Harmonised Index of Consumer Prices Portugal | Monthly | 2010–2025 | `portugal_economic_indicators.inflation_rates` |
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
| `date` | DATE | Observation date |
| `value` | FLOAT | Indicator value |
| `indicator` | STRING | Series name (HICP, Euribor_3M, NPL…) |
| `year` | INTEGER | Extracted year |
| `month` | INTEGER | Extracted month |
| `period` | STRING | Economic period classification (Crisis / Recovery / COVID / Expansion) |

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
| **HICP** | Harmonised Index of Consumer Prices — the standard EU inflation measure used by the ECB to set monetary policy targets |
| **Euribor** | Euro Interbank Offered Rate — the reference rate at which European banks lend to each other; drives mortgage rates across the Eurozone |
| **Spread** | Difference between the housing loan rate and Euribor 12M — measures how much margin banks add above the reference rate |
| **NPL** | Non-Performing Loans — credit where the borrower has stopped making payments; a direct measure of credit risk in the banking sector |
| **YoY** | Year-over-Year — compares a value to the same month in the previous year, removing seasonal noise |
| **Real Rate** | Real interest rate — Euribor minus inflation; when negative, saving money loses real purchasing power |
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

## How to Run

1. Open `pipeline.ipynb` in Google Colab
2. Authenticate with your Google account
3. Set your `PROJECT_ID` in the config cell
4. Run all cells — data is extracted, transformed and loaded to BigQuery automatically
5. Open Power BI → Refresh → dashboard updates

***

## Stage 1 — Python Pipeline

```python
import pandas as pd
import requests
from io import StringIO

SERIES = {
    "HICP":              "5739164",
    "Euribor_3M":        "13168436",
    "Euribor_12M":       "13168437",
    "Housing_Rate":      "12519808",
    "Credit_Volume":     "12519806",
    "NPL":               "12519807",
    "Unemployment":      "12518324",
    "GDP":               "12518325",
}

BASE_CSV_URL = "https://bpstat.bportugal.pt/api/observations/csv/?series_ids={}&language=PT"

def extract_series_csv(series_id, name):
    url = BASE_CSV_URL.format(series_id)
    r = requests.get(url, timeout=30)
    r.raise_for_status()

    df = pd.read_csv(StringIO(r.text), sep=";")

    if df.empty:
        return pd.DataFrame(columns=["date", "value", "indicator"])

    col_map = {}
    for c in df.columns:
        cl = c.strip().lower()
        if "período" in cl or "periodo" in cl:
            col_map[c] = "date"
        elif cl == "valor":
            col_map[c] = "value"

    df = df.rename(columns=col_map)

    if "date" not in df.columns or "value" not in df.columns:
        return pd.DataFrame(columns=["date", "value", "indicator"])

    df["date"]      = pd.to_datetime(df["date"], errors="coerce")
    df["value"]     = pd.to_numeric(df["value"], errors="coerce")
    df["indicator"] = name

    return df[["date", "value", "indicator"]].dropna(subset=["date", "value"])

# Extract all 8 series
print("Extracting 8 BPstat series...")
dfs = []
for name, sid in SERIES.items():
    d = extract_series_csv(sid, name)
    if len(d) > 0:
        print(f"  ✅ {name} → {len(d)} rows")
        dfs.append(d)
    else:
        print(f"  ❌ NO DATA: {name}")

df_master = pd.concat(dfs, ignore_index=True)
df_master = df_master.sort_values(["indicator", "date"]).reset_index(drop=True)
```

The BPstat API returns semicolon-separated CSV files with Portuguese column headers. The extraction function normalises column names dynamically — detecting the date column regardless of accent variations in the header (`período` vs `periodo`) — before parsing types and tagging each row with its series name.

***

### Transform

```python
# Derive year, month and economic period
df_master["year"]  = df_master["date"].dt.year
df_master["month"] = df_master["date"].dt.month
df_master["period"] = pd.cut(
    df_master["year"],
    bins=[2009, 2014, 2019, 2021, 2025],
    labels=["Crisis", "Recovery", "COVID", "Expansion"]
)

# Filter to 2010–2025
df_master = df_master[
    (df_master["year"] >= 2010) & (df_master["year"] <= 2025)
].reset_index(drop=True)

df_master.to_csv("pipeline_complete.csv", index=False)
print(f"✅ Pipeline complete — {len(df_master)} rows across {df_master['indicator'].nunique()} series")
```

The economic period classification uses `pd.cut()` to bin years into four labelled eras: **Crisis** (2010–2014), **Recovery** (2015–2019), **COVID** (2020–2021), and **Expansion** (2022–2025). This column is carried into BigQuery and used directly as a slicer dimension in Power BI.

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
  year,
  month,
  period,
  AVG(value) AS avg_inflation_pct
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicator = 'HICP'
GROUP BY year, month, period
ORDER BY year, month;
```

*Sample output (192 rows total — one per month across all periods):*

| year | month | period | avg_inflation_pct |
|------|-------|--------|-------------------|
| 2010 | 1 | Crisis | 0.80 |
| 2012 | 9 | Crisis | 3.50 |
| 2017 | 4 | Recovery | 4.20 |
| 2021 | 6 | COVID | -3.30 |
| 2023 | 8 | Expansion | 8.00 |

***

**Query 2 — Months Where Inflation Exceeded 3% (ECB Target)**

```sql
SELECT
  year,
  period,
  COUNT(*) AS months_above_3pct
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicator = 'HICP'
  AND value > 3
GROUP BY year, period
ORDER BY year;
```

| year | period | months_above_3pct |
|------|--------|-------------------|
| 2012 | Crisis | 8 |
| 2017 | Recovery | 2 |
| 2018 | Recovery | 2 |
| 2022 | Expansion | 11 |
| 2023 | Expansion | 12 |
| 2024 | Expansion | 12 |
| 2025 | Expansion | 9 |

***

**Query 3 — Euribor 3M vs 12M Evolution by Year**

```sql
SELECT
  year,
  AVG(CASE WHEN indicator = 'Euribor_3M'  THEN value END) AS avg_euribor_3m,
  AVG(CASE WHEN indicator = 'Euribor_12M' THEN value END) AS avg_euribor_12m
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicator IN ('Euribor_3M', 'Euribor_12M')
GROUP BY year
ORDER BY year;
```

Pivoting two series in a single query using conditional `AVG(CASE WHEN)` avoids a JOIN and returns both rates side by side per year — clean for direct use in Power BI line charts.

| year | avg_euribor_3m | avg_euribor_12m |
|------|---------------|----------------|
| 2010 | 0.81 | 1.35 |
| 2013 | 0.22 | 0.54 |
| 2016 | -0.26 | -0.03 |
| 2020 | -0.43 | -0.30 |
| 2022 | 0.34 | 1.09 |
| 2023 | 3.43 | 3.86 |
| 2025 | 2.18 | 2.22 |

***

### Temporal Analysis

**Query 4 — Housing Loan Spread vs Euribor 12M**

```sql
SELECT
  year,
  AVG(CASE WHEN indicator = 'Housing_Rate' THEN value END) AS avg_housing_rate,
  AVG(CASE WHEN indicator = 'Euribor_12M'  THEN value END) AS avg_euribor_12m,
  AVG(CASE WHEN indicator = 'Housing_Rate' THEN value END) -
  AVG(CASE WHEN indicator = 'Euribor_12M'  THEN value END) AS avg_spread
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicator IN ('Housing_Rate', 'Euribor_12M')
GROUP BY year
ORDER BY year;
```

The `avg_spread` column measures how much margin banks charged above the reference rate each year — the core metric behind one of the project's key findings.

| year | avg_housing_rate | avg_euribor_12m | avg_spread |
|------|-----------------|----------------|-----------|
| 2010 | 1.56 | 1.35 | 0.21 |
| 2012 | 1.80 | 1.11 | 0.68 |
| 2016 | 0.25 | -0.03 | 0.28 |
| 2020 | 0.06 | -0.30 | 0.36 |
| 2022 | 0.27 | 1.09 | -0.82 |
| 2023 | 2.61 | 3.86 | -1.25 |
| 2025 | 1.87 | 2.22 | -0.35 |

***

**Query 5 — YoY Inflation Variation with LAG()**

```sql
WITH hicp AS (
  SELECT date, year, month, period, value AS inflation
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'HICP'
)
SELECT
  date, year, month, period, inflation,
  LAG(inflation, 12) OVER (ORDER BY date)                           AS inflation_12m_prior,
  ROUND((inflation - LAG(inflation, 12) OVER (ORDER BY date)), 2)   AS yoy_change
FROM hicp
ORDER BY date;
```

`LAG(inflation, 12)` looks back exactly 12 rows in the time-ordered partition — equivalent to the same month in the prior year — computing a true YoY delta without any calendar join.

*Sample output (first 12 months return null for `inflation_12m_prior` — no prior year available):*

| date | period | inflation | inflation_12m_prior | yoy_change |
|------|--------|-----------|---------------------|-----------|
| 2011-01-31 | Crisis | 2.60 | 0.80 | 1.80 |
| 2012-09-30 | Crisis | 3.50 | 2.40 | 1.10 |
| 2020-09-30 | COVID | -1.40 | 0.30 | -1.70 |
| 2022-04-30 | Expansion | 5.30 | -2.10 | 7.40 |
| 2024-08-31 | Expansion | 3.10 | 8.00 | -4.90 |

***

**Query 6 — 12-Month Moving Average of Inflation**

```sql
WITH hicp AS (
  SELECT date, year, month, period, value AS inflation
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'HICP'
)
SELECT
  date, year, month, period, inflation,
  AVG(inflation) OVER (
    ORDER BY date
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
  ) AS rolling_avg_12m
FROM hicp
ORDER BY date;
```

`ROWS BETWEEN 11 PRECEDING AND CURRENT ROW` creates a rolling 12-month window that smooths out short-term spikes and reveals the true underlying inflation trend.

*Sample output — note how the rolling average lags behind sharp moves:*

| date | period | inflation | rolling_avg_12m |
|------|--------|-----------|----------------|
| 2012-12-31 | Crisis | 3.40 | 3.16 |
| 2021-06-30 | COVID | -3.30 | -0.83 |
| 2022-06-30 | Expansion | 5.50 | 2.65 |
| 2023-08-31 | Expansion | 8.00 | 6.45 |
| 2025-12-31 | Expansion | 4.20 | 3.57 |

***

### Advanced — Window Functions & CTEs

**Query 7 — Top 5 Inflation Months per Economic Period (DENSE_RANK)**

```sql
WITH hicp AS (
  SELECT date, year, month, period, value AS inflation
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'HICP'
),
ranked AS (
  SELECT
    date, year, month, period, inflation,
    DENSE_RANK() OVER (
      PARTITION BY period
      ORDER BY inflation DESC
    ) AS rank_in_period
  FROM hicp
)
SELECT date, year, month, period, inflation, rank_in_period
FROM ranked
WHERE rank_in_period <= 5
ORDER BY period, rank_in_period, date;
```

`DENSE_RANK()` is used instead of `RANK()` to avoid gaps when tied values exist — ensuring every period always produces exactly 5 results regardless of ties.

| date | period | inflation | rank_in_period |
|------|--------|-----------|---------------|
| 2023-08-31 | Expansion | 8.00 | 1 |
| 2023-06-30 | Expansion | 7.90 | 2 |
| 2023-05-31 | Expansion | 7.80 | 3 |
| 2023-07-31 | Expansion | 7.30 | 4 |
| 2023-04-30 | Expansion | 7.10 | 5 |
| 2012-09-30 | Crisis | 3.50 | 1 |
| 2012-08-31 | Crisis | 3.40 | 2 |
| 2012-12-31 | Crisis | 3.40 | 2 |
| 2017-04-30 | Recovery | 4.20 | 1 |
| 2018-07-31 | Recovery | 3.80 | 2 |
| 2021-11-30 | COVID | 2.40 | 1 |
| 2021-12-31 | COVID | 2.10 | 2 |

***

**Query 8 — Euribor vs NPL Correlation (Quarterly CTE)**

```sql
WITH euribor AS (
  SELECT
    DATE_TRUNC(date, QUARTER) AS quarter,
    AVG(CASE WHEN indicator = 'Euribor_3M' THEN value END) AS avg_euribor_3m
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'Euribor_3M'
  GROUP BY quarter
),
npl AS (
  SELECT
    DATE_TRUNC(date, QUARTER) AS quarter,
    AVG(value)                AS avg_npl
  FROM `portugal_economic_indicators.credit_macro`
  WHERE indicator = 'NPL'
  GROUP BY quarter
)
SELECT
  e.quarter,
  e.avg_euribor_3m,
  n.avg_npl
FROM euribor e
JOIN npl n ON e.quarter = n.quarter
ORDER BY e.quarter;
```

`DATE_TRUNC(..., QUARTER)` aligns the monthly Euribor series with the quarterly NPL series before joining — without this normalisation the JOIN would return no matches due to date granularity mismatch.

*Sample output — last 10 quarters showing the Euribor surge and NPL response:*

| quarter | avg_euribor_3m | avg_npl |
|---------|---------------|--------|
| 2022-10-01 | 1.43 | 0.04 |
| 2023-01-01 | 2.34 | 0.04 |
| 2023-04-01 | 3.18 | 0.04 |
| 2023-07-01 | 3.68 | 0.05 |
| 2023-10-01 | 3.97 | 0.05 |
| 2024-01-01 | 3.92 | 0.06 |
| 2024-04-01 | 3.85 | 0.06 |
| 2024-07-01 | 3.58 | 0.07 |
| 2024-10-01 | 3.00 | 0.07 |
| 2025-01-01 | 2.70 | 0.08 |

***

**Query 9 — Months of Negative Real Rate (Inflation > Euribor)**

```sql
WITH inflation AS (
  SELECT date, value AS inflation
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'HICP'
),
euribor AS (
  SELECT date, value AS euribor_3m
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'Euribor_3M'
)
SELECT
  i.date,
  i.inflation,
  e.euribor_3m,
  (e.euribor_3m - i.inflation) AS real_rate
FROM inflation i
JOIN euribor e ON i.date = e.date
WHERE (e.euribor_3m - i.inflation) < 0
ORDER BY i.date;
```

Returns every month where the real rate was negative — the period where saving money actively lost purchasing power. This result feeds directly into the KPI card on Page 3 of the dashboard.

*Sample output — 180 rows total, spanning 2010 to 2025:*

| date | inflation | euribor_3m | real_rate |
|------|-----------|-----------|----------|
| 2010-01-31 | 0.80 | 0.68 | -0.12 |
| 2012-09-30 | 3.50 | 0.25 | -3.25 |
| 2017-04-30 | 4.20 | -0.33 | -4.53 |
| 2022-09-30 | 6.80 | 1.01 | -5.79 |
| 2023-08-31 | 8.00 | 3.78 | -4.22 |
| 2024-03-31 | 5.30 | 3.92 | -1.38 |
| 2025-12-31 | 4.20 | 2.05 | -2.15 |

***

**Query 10 — Inflation Percentile by Decade (2010s vs 2020s)**

```sql
WITH hicp AS (
  SELECT
    year,
    CASE
      WHEN year BETWEEN 2010 AND 2019 THEN '2010s'
      WHEN year BETWEEN 2020 AND 2029 THEN '2020s'
    END AS decade,
    value AS inflation
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicator = 'HICP'
    AND year BETWEEN 2010 AND 2025
)
SELECT
  decade,
  APPROX_QUANTILES(inflation, 2)[OFFSET(1)]  AS median_inflation,
  APPROX_QUANTILES(inflation, 10)[OFFSET(9)] AS p90_inflation
FROM hicp
GROUP BY decade
ORDER BY decade;
```

`APPROX_QUANTILES` computes the median (`[OFFSET(1)]` of a 2-quantile split) and the 90th percentile (`[OFFSET(9)]` of a 10-quantile split) — comparing the full distribution of inflation between decades rather than just comparing averages.

| decade | median_inflation | p90_inflation |
|--------|----------------|--------------|
| 2010s | 1.50 | 3.00 |
| 2020s | 3.80 | 6.40 |

The 2020s median (3.8%) already exceeds the 2010s 90th percentile (3.0%) — meaning inflation in the post-COVID era was structurally higher than even the worst months of the previous decade.

***

## Stage 3 — Power BI Dashboard

Connected Power BI Desktop to BigQuery via the native **Get Data → Google BigQuery** connector (Import mode). A central `Calendar` table was created as a date bridge to allow cross-table filtering between `inflation_rates`, `interest_rates_mvp`, and `credit_macro`.

```dax
Calendar = CALENDAR(DATE(2010,1,1), DATE(2025,12,31))
```

Relations defined: `Calendar[Date]` → `credit_macro[date]` (1:*) and `Calendar[Date]` → `inflation_rates[date]` (1:*), with single-direction filters. This is the architectural key of the model — without it, cross-table line charts return empty results.

![Data Model](https://github.com/guilhermeferreira24/portugal-economic-indicators-pipeline/blob/main/calendario.png?raw=true)

***

### DAX Measures

**Page 1 — Inflation Overview**

```dax
// 12-month rolling average of inflation
Rolling 12M Inflation =
CALCULATE(
    AVERAGE(inflation_rates[value]),
    DATESINPERIOD(
        inflation_rates[date],
        MAX(inflation_rates[date]),
        -12,
        MONTH
    )
)

// Months where inflation exceeded the ECB 2% target
Months Above 2% =
CALCULATE(
    COUNTROWS(inflation_rates),
    inflation_rates[indicator] = "HICP",
    inflation_rates[value] > 2
)

// Months where inflation was at or below 2%
Months Below 2% =
CALCULATE(
    COUNTROWS(inflation_rates),
    inflation_rates[indicator] = "HICP",
    inflation_rates[value] <= 2
)
```

**Page 2 — Interest Rates Analysis**

```dax
// Most recent Euribor 3M value
Euribor3M_Current =
CALCULATE(
    LASTNONBLANK(interest_rates_mvp[value], 1),
    interest_rates_mvp[indicator] = "Euribor_3M"
)

// Housing loan spread over Euribor 12M
Housing_Spread =
CALCULATE(
    AVERAGE(inflation_rates[value]),
    inflation_rates[indicator] = "Housing_Rate"
) -
CALCULATE(
    AVERAGE(interest_rates_mvp[value]),
    interest_rates_mvp[indicator] = "Euribor_12M"
)
```

**Page 3 — Credit & Risk**

```dax
// Current NPL ratio (most recent month)
NPL_Current =
VAR LastDate =
    CALCULATE(
        MAX(credit_macro[date]),
        credit_macro[indicator] = "NPL"
    )
RETURN
    CALCULATE(
        MAX(credit_macro[value]),
        credit_macro[indicator] = "NPL",
        credit_macro[date] = LastDate
    )

// Peak NPL ratio (historical maximum)
NPL_Peak =
CALCULATE(
    MAX(credit_macro[value]),
    credit_macro[indicator] = "NPL"
)

// Months where real rate was negative (inflation > Euribor 3M)
Months_Negative_Real_Rate =
COUNTROWS(
    FILTER(
        VALUES(inflation_rates[date]),
        CALCULATE(
            AVERAGE(inflation_rates[value]),
            inflation_rates[indicator] = "HICP"
        ) >
        CALCULATE(
            AVERAGE(interest_rates_mvp[value]),
            interest_rates_mvp[indicator] = "Euribor_12M"
        )
    )
)

// Euribor 12M values pulled into credit_macro context for dual-axis chart
Euribor12M_Val =
CALCULATE(
    AVERAGE(inflation_rates[value]),
    inflation_rates[indicator] = "Euribor_12M"
)

// NPL values for dual-axis chart
NPL_Val =
CALCULATE(
    AVERAGE(credit_macro[value]),
    credit_macro[indicator] = "NPL"
)
```

`DATESINPERIOD` with `-12, MONTH` creates a true rolling window anchored to the last visible date in the visual — unlike `ROWS BETWEEN` in SQL, it respects filter context from slicers. The `VAR/RETURN` pattern in `NPL_Current` avoids the `LASTNONBLANK` trap of returning the last alphabetical value instead of the most recent chronological one.

***

### Dashboard Pages

**Page 1 — Inflation Analysis · Portugal 2010–2025**

![Inflation Analysis](https://github.com/guilhermeferreira24/portugal-economic-indicators-pipeline/blob/main/inflationanalysis.png?raw=true)

Key visuals: KPI card (Avg Inflation: 1.27%), stacked bar chart (Months Above/Below 2% per year 2010–2025), dual-line chart (Inflation Monthly Trend + Rolling 12M Inflation overlay with ECB 2% dashed reference line), slicer (economic period: COVID / Crisis / Expansion / Recovery)

***

**Page 2 — Interest Rates Analysis · Euribor Trends & Housing Spread 2010–2025**

![Interest Rates Analysis](https://github.com/guilhermeferreira24/portugal-economic-indicators-pipeline/blob/main/interestrates.png?raw=true)

Key visuals: KPI cards (Avg Euribor 12M: 0.92, Avg Euribor 3M: 0.65, Avg Housing Spread: 1.16), dual-line chart (Euribor 3M vs 12M Historical Trend), area chart (Housing Rate Spread vs Euribor 12M), matrix (Avg Spread by Economic Period — COVID: 0.05 / Recovery: 0.23 / Crisis: 1.90 / Expansion: 1.97)

***

**Page 3 — Credit & Risk Analysis · NPL Trends, Credit Volume & Real Rate Impact**

![Credit & Risk Analysis](https://github.com/guilhermeferreira24/portugal-economic-indicators-pipeline/blob/main/creditrisk.png?raw=true)

Key visuals: KPI cards (Current NPL Ratio: 1.42, Peak NPL Ratio: 4.66, Months of Negative Real Rate: 181), dual-line chart (Euribor 12M vs NPL Rate 2010–2025), area chart (Avg New Housing Loan Rate %)

***

## Key Findings

- **181 months of negative real rate** — from 2008 to 2022, inflation exceeded Euribor 3M for roughly 70% of the period, meaning saving money actively lost purchasing power for over 15 years
- **NPL peaked at 4.66% during 2011–2012** and has since recovered to ~1.42% — the crisis era left a lasting scar on Portuguese credit quality before gradual deleveraging took effect
- **Housing spread remained above 1.5pp even when Euribor was negative** — Portuguese banks never fully passed low rates on to mortgage borrowers, maintaining margin throughout the low-rate period
- **Euribor surge in 2022–2023 coincided with inflation peaking and then falling** — the ECB rate hike cycle is clearly visible in the data, with inflation responding within 12–18 months
- **The 2010s inflation distribution is structurally different from the 2020s** — the PERCENTILE_CONT query confirms that the p90 inflation figure in the 2020s exceeds the 2010s median, reflecting how the post-COVID expansion shifted the entire distribution upward

***

## What I Learned

- **`DATESINPERIOD` vs `ROWS BETWEEN`** — DAX rolling windows respect filter context from slicers dynamically; a SQL rolling window is static over the full dataset. The same "12-month average" behaves completely differently depending on the tool
- **`VAR/RETURN` for point-in-time values** — `LASTNONBLANK` returns the last alphabetical value, not the most recent chronological one; wrapping `MAX(date)` in a `VAR` and using it as a filter in `RETURN` is the reliable pattern for "value at last date"
- **Date table is mandatory for cross-table visuals** — without a central `Calendar` table, Power BI cannot align time series from different tables on the same axis. Adding it as a 1:* bridge resolved every empty chart issue immediately
- **`pandas-gbq` `if_exists="replace"`** — ensures clean full refreshes with no duplicate accumulation across pipeline runs; important when re-running with updated API data
- **BPstat CSV headers are locale-dependent** — the date column header varies between `período` and `periodo` depending on the browser/request language; dynamic column detection with `.strip().lower()` makes the extraction function robust to this
- **`DATE_TRUNC(..., QUARTER)` for cross-frequency joins** — aligning monthly Euribor with quarterly NPL data requires truncating both to quarter before joining; without this the JOIN returns zero matches due to date granularity mismatch
- **`APPROX_QUANTILES` vs `PERCENTILE_CONT`** — BigQuery uses `APPROX_QUANTILES(col, N)[OFFSET(k)]` where N is the number of buckets; SQL Server/PostgreSQL use `PERCENTILE_CONT(0.x) WITHIN GROUP (ORDER BY col)`. Same concept, completely different syntax

***

## Source

| | |
|---|---|
| **Data** | [Banco de Portugal — BPstat API](https://bpstat.bportugal.pt) |
| **Python** | Google Colab |
| **SQL** | Google BigQuery Sandbox |
| **BI Tool** | Microsoft Power BI Desktop |
| **Repository** | [github.com/guilhermeferreira24/portugal-economic-indicators-pipeline](https://github.com/guilhermeferreira24/portugal-economic-indicators-pipeline) |
