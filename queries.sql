-- ============================================================
-- Portugal Economic Indicators Pipeline
-- SQL Analysis — Google BigQuery
-- Dataset: portugal_economic_indicators
-- ============================================================


-- ------------------------------------------------------------
-- BASIC EXPLORATION
-- ------------------------------------------------------------

-- Query 1 — Average Inflation by Year and Economic Period
SELECT
  ano,
  mes,
  periodo,
  AVG(valor) AS inflacao_media_pct
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador = 'IHPC'
GROUP BY ano, mes, periodo
ORDER BY ano, mes;


-- Query 2 — Months Where Inflation Exceeded 3% (ECB Target)
SELECT
  ano,
  periodo,
  COUNT(*) AS meses_acima_3pct
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador = 'IHPC'
  AND valor > 3
GROUP BY ano, periodo
ORDER BY ano;


-- Query 3 — Euribor 3M vs 12M Evolution by Year
SELECT
  ano,
  AVG(CASE WHEN indicador = 'Euribor_3M'  THEN valor END) AS euribor_3m_media,
  AVG(CASE WHEN indicador = 'Euribor_12M' THEN valor END) AS euribor_12m_media
FROM `portugal_economic_indicators.inflation_rates`
WHERE indicador IN ('Euribor_3M', 'Euribor_12M')
GROUP BY ano
ORDER BY ano;


-- ------------------------------------------------------------
-- TEMPORAL ANALYSIS
-- ------------------------------------------------------------

-- Query 4 — Housing Loan Spread vs Euribor 12M
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


-- Query 5 — YoY Inflation Variation with LAG()
WITH ihpc AS (
  SELECT
    data,
    ano,
    mes,
    periodo,
    valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
)
SELECT
  data,
  ano,
  mes,
  periodo,
  inflacao,
  LAG(inflacao, 12) OVER (ORDER BY data)                        AS inflacao_12m_antes,
  ROUND((inflacao - LAG(inflacao, 12) OVER (ORDER BY data)), 2) AS variacao_yoy
FROM ihpc
ORDER BY data;


-- Query 6 — 12-Month Moving Average of Inflation
WITH ihpc AS (
  SELECT
    data,
    ano,
    mes,
    periodo,
    valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
)
SELECT
  data,
  ano,
  mes,
  periodo,
  inflacao,
  AVG(inflacao) OVER (
    ORDER BY data
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
  ) AS media_movel_12m
FROM ihpc
ORDER BY data;


-- ------------------------------------------------------------
-- ADVANCED — WINDOW FUNCTIONS & CTEs
-- ------------------------------------------------------------

-- Query 7 — Top 5 Inflation Months per Economic Period (DENSE_RANK)
WITH ihpc AS (
  SELECT
    data,
    ano,
    mes,
    periodo,
    valor AS inflacao
  FROM `portugal_economic_indicators.inflation_rates`
  WHERE indicador = 'IHPC'
),
ranked AS (
  SELECT
    data,
    ano,
    mes,
    periodo,
    inflacao,
    DENSE_RANK() OVER (
      PARTITION BY periodo
      ORDER BY inflacao DESC
    ) AS rank_in_periodo
  FROM ihpc
)
SELECT
  data,
  ano,
  mes,
  periodo,
  inflacao,
  rank_in_periodo
FROM ranked
WHERE rank_in_periodo <= 5
ORDER BY periodo, rank_in_periodo, data;


-- Query 8 — Euribor vs NPL Correlation (Quarterly CTE)
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


-- Query 9 — Months of Negative Real Rate (Inflation > Euribor)
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


-- Query 10 — Inflation Percentile by Decade (2010s vs 2020s)
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
