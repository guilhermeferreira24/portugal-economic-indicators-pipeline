import pandas as pd
import requests
from io import StringIO

# ============================================================
# Portugal Economic Indicators Pipeline
# Stage 1 — Extract
# ============================================================

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

    df["data"]      = pd.to_datetime(df["data"], errors="coerce")
    df["valor"]     = pd.to_numeric(df["valor"], errors="coerce")
    df["indicador"] = nome

    return df[["data", "valor", "indicador"]].dropna(subset=["data", "valor"])

print("Pipeline completo - Extrair 8 séries BPstat")
dfs = []
for nome, sid in SERIES.items():
    d = extract_series_csv(sid, nome)
    if len(d) > 0:
        print(f"  OK: {nome} -> {len(d)} linhas")
        dfs.append(d)
    else:
        print(f"  SEM DADOS: {nome}")

df_master = pd.concat(dfs, ignore_index=True)
df_master = df_master.sort_values(["indicador", "data"]).reset_index(drop=True)

# ============================================================
# Stage 2 — Transform
# ============================================================

df_master["ano"] = df_master["data"].dt.year
df_master["mes"] = df_master["data"].dt.month
df_master["periodo"] = pd.cut(
    df_master["ano"],
    bins=[2009, 2014, 2019, 2021, 2025],
    labels=["Crise", "Recuperacao", "COVID", "Expansao"]
)

df_master = df_master[(df_master["ano"] >= 2010) & (df_master["ano"] <= 2025)].reset_index(drop=True)

# ============================================================
# Stage 3 — Load to BigQuery
# ============================================================

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

print(f"\n✅ Pipeline concluído!")
print(f"📊 Total linhas: {len(df_master)}")
print(f"📈 Séries: {df_master['indicador'].nunique()}")
print(df_master["indicador"].value_counts())
print("\nDataset pronto para BigQuery/Power BI")
