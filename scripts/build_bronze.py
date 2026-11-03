"""Convertit l'export CSV legacy d'Albert's Marketplace en Parquet partitionné (bronze).

Règle du bronze : on garde ce qui est arrivé, tel quel. Aucune ligne supprimée,
aucune colonne supprimée, aucune valeur corrigée. Le script ajoute seulement une
clé de partition, qui devient un dossier (style Hive) :
  - orders       -> month=AAAA-MM (mois de order_date)
  - order_items  -> month=AAAA-MM (mois de la commande, récupéré par jointure)
  - autres       -> ingest_date=AAAA-MM-JJ (jour du chargement)

Par défaut, customer et payment_details sont EXCLUS (mots de passe, cartes, CVV)
en attendant la validation du prof. --include-sensitive les inclut.

Usage :
  python scripts/build_bronze.py --src ~/de/legacy_csv --out ~/de/out/bronze
"""
import argparse
import csv
import pathlib
import re
import shutil
import sys
from datetime import date

import pandas as pd

SENSITIVE = {"customer", "payment_details"}


def write(df: pd.DataFrame, target: pathlib.Path, part_col: str, codec: str) -> tuple[int, int]:
    df.to_parquet(
        target,
        partition_cols=[part_col],
        compression=codec,
        index=False,
        max_partitions=5000,
        basename_template="part-{i}.parquet",
    )
    files = list(target.rglob("*.parquet"))
    return len(files), sum(f.stat().st_size for f in files)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="dossier des CSV legacy")
    ap.add_argument("--out", required=True, help="dossier de sortie (sera vidé)")
    ap.add_argument("--codec", default="snappy", help="snappy (défaut), zstd, gzip...")
    ap.add_argument("--include-sensitive", action="store_true")
    ap.add_argument("--report", default="notes/step2-sizes.csv")
    ap.add_argument("--safe-column-names", action="store_true",
                    help="renomme les colonnes que BigQuery refuse (ex. 'Unnamed: 0' -> 'unnamed_0'), sans toucher aux valeurs")
    args = ap.parse_args()

    src = pathlib.Path(args.src).expanduser()
    out = pathlib.Path(args.out).expanduser()
    if not (src / "orders.csv").exists():
        print(f"ERREUR : {src}/orders.csv introuvable. Vérifiez --src.", file=sys.stderr)
        return 1
    if out.exists():
        shutil.rmtree(out)  # repartir de zéro : pas de vieux fichiers mélangés
    out.mkdir(parents=True)

    ingest_date = date.today().isoformat()
    orders = pd.read_csv(src / "orders.csv", low_memory=False)
    order_month = (
        orders[["order_id"]]
        .assign(month=pd.to_datetime(orders["order_date"]).dt.strftime("%Y-%m"))
        .drop_duplicates("order_id")
    )

    rows_report = []
    print(f"{'table':25s} {'lignes':>10s} {'csv (Mo)':>10s} {'parquet (Mo)':>13s} {'objets':>7s}  partition")
    for path in sorted(src.glob("*.csv")):
        table = path.stem
        if table in SENSITIVE and not args.include_sensitive:
            print(f"{table:25s} {'EXCLUE (données sensibles)':>45s}")
            continue

        df = orders.copy() if table == "orders" else pd.read_csv(path, low_memory=False)
        n_rows = len(df)
        if args.safe_column_names:
            df.columns = [re.sub(r"[^0-9a-zA-Z_]", "_", c).lower() for c in df.columns]
        if table == "orders":
            df["month"] = pd.to_datetime(df["order_date"]).dt.strftime("%Y-%m")
            part = "month"
        elif table == "order_items":
            df = df.merge(order_month, on="order_id", how="left")
            df["month"] = df["month"].fillna("unknown")
            part = "month"
        else:
            df["ingest_date"] = ingest_date
            part = "ingest_date"
        assert len(df) == n_rows, f"{table} : le nombre de lignes a changé ({n_rows} -> {len(df)})"

        n_obj, size = write(df, out / table, part, args.codec)
        csv_size = path.stat().st_size
        print(f"{table:25s} {n_rows:>10,} {csv_size/1e6:>10.2f} {size/1e6:>13.2f} {n_obj:>7}  {part}")
        rows_report.append([table, n_rows, csv_size, size, n_obj, part, args.codec])

    report = pathlib.Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["table", "rows", "csv_bytes", "parquet_bytes", "objects", "partition", "codec"])
        w.writerows(rows_report)
    print(f"\nRésumé écrit dans {report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
