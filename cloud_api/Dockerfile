FROM python:3.12-slim@sha256:78387bc3881b8273120a12ebe6c1ab22b018ccc2c9adf565ae1ac9b536e184ea

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY cloud_api/__init__.py cloud_api/app.py cloud_api/business.py cloud_api/server.py ./cloud_api/

RUN python -m compileall -q cloud_api \
    && addgroup --system --gid 10001 gardenjournal \
    && adduser --system --uid 10001 --ingroup gardenjournal --home /nonexistent --no-create-home gardenjournal \
    && mkdir -p /var/lib/gardenjournal \
    && chown -R gardenjournal:gardenjournal /app /var/lib/gardenjournal

USER gardenjournal
EXPOSE 8080

ENTRYPOINT ["python", "-m", "cloud_api.server"]
