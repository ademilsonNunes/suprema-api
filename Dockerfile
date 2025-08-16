FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=America/Sao_Paulo \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 ca-certificates apt-transport-https \
    build-essential gcc g++ make \
    unixodbc unixodbc-dev libgssapi-krb5-2 \
    supervisor procps vim \
    redis-server redis-tools \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
 && echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
    > /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/redis /var/log/redis \
 && chown redis:redis /var/lib/redis /var/log/redis

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY api /app/api
COPY admin_app /app/admin_app
COPY sql /app/sql

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

RUN mkdir -p /var/log/supervisor

EXPOSE 8508 8510 6379

ENV REDIS_URL=redis://127.0.0.1:6379/0 \
    RATE_LIMIT_ALGO=sliding

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8508/health || exit 1

CMD ["/app/start.sh"]
