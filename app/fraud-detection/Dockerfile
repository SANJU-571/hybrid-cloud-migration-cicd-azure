# syntax=docker/dockerfile:1
# Multi-stage build: dependencies are installed in a full Python image, then
# copied into a distroless runtime (no shell, no package manager, non-root).
# The distroless Python 3 image for Debian 12 ships Python 3.11, so the
# builder uses the same minor version.

FROM python:3.11-slim-bookworm AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check --target /deps -r requirements.txt

FROM gcr.io/distroless/python3-debian12:nonroot
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="fraud-detection" \
      org.opencontainers.image.description="N-Financial Bank fraud-detection API" \
      org.opencontainers.image.source="https://github.com/SANJU-571/hybrid-cloud-migration-cicd-azure" \
      org.opencontainers.image.licenses="MIT"
ENV PYTHONPATH=/deps \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION} \
    PORT=8080
WORKDIR /app
COPY --from=build /deps /deps
COPY src/fraud_api.py .
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD ["python3", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]
ENTRYPOINT ["python3", "fraud_api.py"]
