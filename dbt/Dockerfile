FROM python:3.12.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DBT_PROFILES_DIR=/usr/app

RUN python -m pip install --no-cache-dir \
        dbt-core==1.12.5 \
        dbt-bigquery==1.12.1 \
    && useradd --create-home --uid 10001 dbt \
    && mkdir -p /usr/app \
    && chown dbt:dbt /usr/app

WORKDIR /usr/app

COPY --chown=dbt:dbt dbt/ ./

USER dbt

RUN dbt deps

ENTRYPOINT ["dbt"]
CMD ["build", "--target", "prod"]