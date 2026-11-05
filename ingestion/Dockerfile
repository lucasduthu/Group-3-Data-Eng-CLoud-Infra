FROM python:3.12.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY ingestion/requirements.txt ./

RUN python -m pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home --uid 10001 ingest

COPY ingestion/extract_orders.py \
     ingestion/extract_customer.py \
     ingestion/consume_clickstream.py \
     ingestion/clickstream.schema.json ./

USER ingest

CMD ["python", "extract_orders.py"]
