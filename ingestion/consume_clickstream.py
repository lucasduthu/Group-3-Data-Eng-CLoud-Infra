"""Consumer du topic clickstream vers le bronze, avec validation et DLQ.

Garantie de livraison : AT-LEAST-ONCE. Les offsets Kafka ne sont commités
qu'après l'écriture réussie du lot (valides + rejetés) dans GCS. Un crash
entre l'écriture et le commit relit le lot : doublons possibles, jamais de
perte. Les doublons sont retirés en silver sur event_id.

Partition de stockage : dt = date de event_time (le jour où l'événement s'est
produit). Un événement en retard atterrit dans un dossier de jour déjà écrit :
on l'accepte, et c'est pour ça que chaque lot est un nouveau fichier (jamais
de réécriture d'un fichier existant).

Validation : chaque message est validé contre le JSON Schema correspondant à
son schema_version. Un message invalide part dans bronze/_dlq/ avec la ligne
d'origine, la raison et l'heure du rejet. Il n'arrête jamais le consumer.

Variables d'environnement :
  KAFKA_BOOTSTRAP    localhost:9092                  (obligatoire)
  BRONZE_BUCKET      albert-de-msc2-26-g03-bronze    (obligatoire)
  CLICKSTREAM_TOPIC  défaut clickstream
  CONSUMER_GROUP     défaut g03-clickstream-to-bronze
  BATCH_SIZE         défaut 2000 messages par lot
  FLUSH_EVERY_S      défaut 60 s entre deux écritures
"""
import json
import logging
import os
import pathlib
import signal
import time
import uuid
from collections import defaultdict
from datetime import datetime, timezone

import pandas as pd
from confluent_kafka import Consumer, KafkaError
from jsonschema import Draft202012Validator, FormatChecker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("consume_clickstream")

BOOTSTRAP = os.environ["KAFKA_BOOTSTRAP"]
BUCKET = os.environ["BRONZE_BUCKET"]
TOPIC = os.environ.get("CLICKSTREAM_TOPIC", "clickstream")
GROUP = os.environ.get("CONSUMER_GROUP", "g03-clickstream-to-bronze")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "2000"))
FLUSH_EVERY_S = int(os.environ.get("FLUSH_EVERY_S", "60"))

SCHEMA_DIR = pathlib.Path(__file__).parent
VALIDATORS = {
    1: Draft202012Validator(
        json.loads((SCHEMA_DIR / "clickstream.schema.json").read_text()),
        format_checker=FormatChecker(),
    ),
}

running = True
def stop(*_):
    global running
    running = False
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)


def validate(raw: bytes):
    """Retourne (event, None) si valide, (None, raison) sinon."""
    try:
        event = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return None, f"invalid_json: {exc}"
    if not isinstance(event, dict):
        return None, "not_an_object"
    version = event.get("schema_version")
    validator = VALIDATORS.get(version)
    if validator is None:
        return None, f"unknown_schema_version: {version!r}"
    errors = sorted(validator.iter_errors(event), key=lambda e: list(e.path))
    if errors:
        first = errors[0]
        where = "/".join(map(str, first.path)) or "(root)"
        return None, f"schema_v{version}: {where}: {first.message}"
    return event, None


def flush(valid: list, rejected: list) -> None:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    run = uuid.uuid4().hex[:8]

    by_day = defaultdict(list)
    for e in valid:
        by_day[e["event_time"][:10]].append(e)
    for dt, events in by_day.items():
        path = f"gs://{BUCKET}/bronze/clickstream/dt={dt}/batch-{stamp}-{run}.parquet"
        pd.DataFrame(events).to_parquet(path, index=False)
        log.info("%d événements -> %s", len(events), path)

    if rejected:
        dt = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        path = f"gs://{BUCKET}/bronze/_dlq/clickstream/dt={dt}/rejected-{stamp}-{run}.parquet"
        pd.DataFrame(rejected).to_parquet(path, index=False)
        log.warning("%d rejetés -> %s", len(rejected), path)


def main() -> None:
    consumer = Consumer({
        "bootstrap.servers": BOOTSTRAP,
        "group.id": GROUP,
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,  # on commite nous-mêmes, APRÈS l'écriture
    })
    consumer.subscribe([TOPIC])
    valid, rejected, last_flush = [], [], time.monotonic()

    try:
        while running:
            msg = consumer.poll(1.0)
            if msg is not None:
                if msg.error():
                    if msg.error().code() != KafkaError._PARTITION_EOF:
                        log.error("erreur kafka : %s", msg.error())
                else:
                    event, reason = validate(msg.value())
                    if event is not None:
                        event["_kafka_partition"] = msg.partition()
                        event["_kafka_offset"] = msg.offset()
                        valid.append(event)
                    else:
                        rejected.append({
                            "raw": msg.value().decode("utf-8", errors="replace"),
                            "reason": reason,
                            "rejected_at": datetime.now(timezone.utc).isoformat(),
                            "kafka_partition": msg.partition(),
                            "kafka_offset": msg.offset(),
                        })

            due = time.monotonic() - last_flush >= FLUSH_EVERY_S
            if (len(valid) + len(rejected) >= BATCH_SIZE) or (due and (valid or rejected)):
                flush(valid, rejected)                 # 1. écrire
                consumer.commit(asynchronous=False)    # 2. PUIS commiter (at-least-once)
                valid, rejected, last_flush = [], [], time.monotonic()
    finally:
        if valid or rejected:
            flush(valid, rejected)
            consumer.commit(asynchronous=False)
        consumer.close()


if __name__ == "__main__":
    main()
