# Base com Python 3.11
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=America/Sao_Paulo \
    DEBIAN_FRONTEND=noninteractive

# Dependências do sistema
# - build-essential + unixodbc-dev para compilar pyodbc
# - msodbcsql18 (driver Microsoft p/ SQL Server)
# - redis-server
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 ca-certificates apt-transport-https \
    build-essential gcc g++ make \
    unixodbc unixodbc-dev libgssapi-krb5-2 \
    supervisor procps vim \
    redis-server \
  && rm -rf /var/lib/apt/lists/*

# Repositório Microsoft (ODBC 18)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
 && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list \
    | tee /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*

# Diretório de trabalho
WORKDIR /app

# Requisitos Python
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Código da API e Admin
# Estrutura esperada:
# /app/api/*.py   (main.py, db.py, models.py, rate_limiter.py)
# /app/admin_app/streamlit_admin.py
# /app/sql/*.sql  (opcional)
COPY api /app/api
COPY admin_app /app/admin_app
COPY sql /app/sql

# Supervisor e entrypoint
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Redis config mínima (opcional)
# Se quiser customizar: COPY redis.conf /etc/redis/redis.conf
# Por padrão usaremos o /etc/redis/redis.conf que já vem no pacote

# Portas:
# - 8508 (FastAPI)
# - 8510 (Streamlit)
# - 6379 (Redis) -> você pode não expor externamente se não quiser acessar de fora
EXPOSE 8508 8510 6379

# Variáveis default (podem ser sobrescritas por .env)
ENV REDIS_URL=redis://127.0.0.1:6379/0 \
    RATE_LIMIT_ALGO=sliding \
    DB_CONNECTION_TIMEOUT=300 \
    DB_COMMAND_TIMEOUT=600 \
    POOL_TIMEOUT=300 \
    HTTP_TIMEOUT=900

# HEALTHCHECK simples na API
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8508/health || exit 1

CMD ["/app/start.sh"]
