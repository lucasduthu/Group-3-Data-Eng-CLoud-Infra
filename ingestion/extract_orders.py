"""Extracteur incrémental de la table orders vers le bronze.

- SQL brut via psycopg, sans ORM.
- Curseur (dernier order_id lu) stocké dans le bucket : il survit au redémarrage
  de la machine comme du conteneur.
- Credentials lus dans l'environnement (DATABASE_URL).
- Retries avec délai exponentiel, abandon après MAX_ATTEMPTS.

Garantie : at-least-once. Le curseur n'avance qu'APRÈS l'écriture du Parquet ;
un crash entre les deux relit le même lot au prochain run (doublons possibles,
dédoublonnés en silver).

Ne voit pas : les UPDATE et les DELETE sur des commandes déjà lues.

Mode intervalle (pour le DAG du step 7) : si INTERVAL_START est défini, on lit
les commandes de [INTERVAL_START, INTERVAL_END) et on écrit à un chemin fixe
par jour. Rejouer le même intervalle remplace le même objet : idempotent. Ce
mode ne lit ni n'avance le curseur.

Variables d'environnement :
  DATABASE_URL    postgresql://user:pass@host:5432/marketplace   (obligatoire)
  BRONZE_BUCKET   albert-de-msc2-26-g03-bronze                   (obligatoire)
  BATCH_LIMIT     nombre max de lignes par run (défaut 50000)
  INTERVAL_START  2026-08-01 (optionnel, active le mode intervalle)
  INTERVAL_END    2026-08-02 (exclu, obligatoire avec INTERVAL_START)
"""
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone

import pandas as pd
import psycopg
from google.cloud import storage

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("extract_orders")

DATABASE_URL = os.environ["DATABASE_URL"]
BUCKET = os.environ["BRONZE_BUCKET"]
BATCH_LIMIT = int(os.environ.get("BATCH_LIMIT", "50000"))
INTERVAL_START = os.environ.get("INTERVAL_START")
INTERVAL_END = os.environ.get("INTERVAL_END")
MAX_ATTEMPTS = 5
BASE_DELAY_S = 2

STATE_PATH = "bronze/_state/extract_orders.json"
TABLE = "orders"
CURSOR_COL = "order_id"

gcs = storage.Client()
bucket = gcs.bucket(BUCKET)


def read_cursor() -> int:
    blob = bucket.blob(STATE_PATH)
    if not blob.exists():
        log.info("pas de curseur : premier run, lecture depuis le début")
        return 0
    state = json.loads(blob.download_as_text())
    return int(state["last_order_id"])


def write_cursor(last_id: int, rows: int) -> None:
    state = {
        "last_order_id": last_id,
        "rows_last_run": rows,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    bucket.blob(STATE_PATH).upload_from_string(json.dumps(state), content_type="application/json")


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
    last_id = read_cursor()
    log.info("curseur actuel : %s > %d", CURSOR_COL, last_id)

    sql = f"SELECT * FROM {TABLE} WHERE {CURSOR_COL} > %s ORDER BY {CURSOR_COL} LIMIT %s"
    with connect_with_retry() as conn, conn.cursor() as cur:
        cur.execute(sql, (last_id, BATCH_LIMIT))
        rows = cur.fetchall()
        cols = [c.name for c in cur.description]

    if not rows:
        log.info("rien de nouveau")
        return 0

    df = pd.DataFrame(rows, columns=cols)
    extracted_at = datetime.now(timezone.utc)
    df["_extracted_at"] = extracted_at  # métadonnée maison, l'équivalent de _airbyte_extracted_at

    dt = extracted_at.strftime("%Y-%m-%d")
    stamp = extracted_at.strftime("%Y%m%dT%H%M%S")
    path = f"gs://{BUCKET}/bronze/extract/{TABLE}/extract_date={dt}/{TABLE}-{stamp}-from-{last_id}.parquet"
    df.to_parquet(path, index=False, compression="snappy")  # nécessite gcsfs

    new_last = int(df[CURSOR_COL].max())
    write_cursor(new_last, len(df))  # APRÈS l'écriture : at-least-once
    log.info("%d lignes -> %s ; curseur %d -> %d", len(df), path, last_id, new_last)
    return 0


def run_interval() -> int:
    sql = f"SELECT * FROM {TABLE} WHERE order_date >= %s AND order_date < %s ORDER BY {CURSOR_COL}"
    with connect_with_retry() as conn, conn.cursor() as cur:
        cur.execute(sql, (INTERVAL_START, INTERVAL_END))
        rows = cur.fetchall()
        cols = [c.name for c in cur.description]
    df = pd.DataFrame(rows, columns=cols)
    df["_extracted_at"] = datetime.now(timezone.utc)
    # Chemin déterministe : un rerun du même intervalle remplace le même objet
    path = f"gs://{BUCKET}/bronze/extract/{TABLE}/extract_date={INTERVAL_START}/{TABLE}.parquet"
    df.to_parquet(path, index=False, compression="snappy")
    log.info("%d lignes -> %s", len(df), path)
    return 0


if __name__ == "__main__":
    sys.exit(run_interval() if INTERVAL_START else main())
