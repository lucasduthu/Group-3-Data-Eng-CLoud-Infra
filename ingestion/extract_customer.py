"""Extracteur de la table customer vers le bronze, SANS la colonne pwd.

- SQL brut via psycopg, sans ORM, avec une LISTE DE COLONNES EXPLICITE :
  jamais de SELECT *, pour qu'une colonne secrète (pwd) ou ajoutée plus tard
  n'arrive jamais dans le bronze sans décision.
- Credentials lus dans l'environnement (DATABASE_URL).
- Retries avec délai exponentiel, abandon après MAX_ATTEMPTS.

Instantané complet à chaque run : c_id est une chaîne aléatoire (pas de
valeur croissante ni de date de création), donc aucun curseur incrémental
n'est possible. Le fichier du jour a un chemin fixe : rejouer le même jour
remplace le même objet (idempotent).

Ne voit pas : l'historique des changements dans la journée (seul l'état au
moment du run est gardé).

Variables d'environnement :
  DATABASE_URL   postgresql://user:pass@host:5432/marketplace   (obligatoire)
  BRONZE_BUCKET  albert-de-msc2-26-g03-bronze                   (obligatoire)
"""
import logging
import os
import sys
import time
from datetime import datetime, timezone

import pandas as pd
import psycopg

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("extract_customer")

DATABASE_URL = os.environ["DATABASE_URL"]
BUCKET = os.environ["BRONZE_BUCKET"]
MAX_ATTEMPTS = 5
BASE_DELAY_S = 2

TABLE = "customer"
COLUMNS = ["c_id", "fname", "lname", "phone", "email"]   # pwd exclu volontairement


def connect_with_retry() -> psycopg.Connection:
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            return psycopg.connect(DATABASE_URL, connect_timeout=10)
        except psycopg.OperationalError as exc:
            if attempt == MAX_ATTEMPTS:
                log.error("abandon après %d tentatives : %s", attempt, exc)
                raise
            delay = BASE_DELAY_S * 2 ** (attempt - 1)  # 2, 4, 8, 16 s
            log.warning("connexion échouée (tentative %d/%d), nouvel essai dans %ds : %s",
                        attempt, MAX_ATTEMPTS, delay, exc)
            time.sleep(delay)


def main() -> int:
    sql = f"SELECT {', '.join(COLUMNS)} FROM {TABLE} ORDER BY c_id"
    with connect_with_retry() as conn, conn.cursor() as cur:
        cur.execute(sql)
        rows = cur.fetchall()

    df = pd.DataFrame(rows, columns=COLUMNS)
    extracted_at = datetime.now(timezone.utc)
    df["_extracted_at"] = extracted_at

    dt = extracted_at.strftime("%Y-%m-%d")
    path = f"gs://{BUCKET}/bronze/extract/{TABLE}/extract_date={dt}/{TABLE}.parquet"
    df.to_parquet(path, index=False, compression="snappy")  # nécessite gcsfs
    log.info("%d lignes, colonnes %s -> %s", len(df), list(df.columns), path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
