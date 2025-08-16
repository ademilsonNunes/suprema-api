#!/bin/bash
# Script para corrigir tudo automaticamente - Container Único

set -e

echo "🚀 Suprema API - Correção Automática (Container Único)"
echo "=================================================="

# 1. Parar containers existentes
echo "⏹️ Parando containers existentes..."
docker-compose down 2>/dev/null || true

# 2. Criar api/__init__.py
echo "📁 Criando api/__init__.py..."
mkdir -p api
echo "# API Package" > api/__init__.py

# 3. Criar diretórios
echo "📁 Criando diretórios necessários..."
mkdir -p logs sql admin_app

# 4. Criar docker-compose.yml
echo "🐳 Criando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
services:
  suprema:
    build: .
    container_name: suprema_allinone
    restart: unless-stopped
    env_file: .env
    ports:
      - "8508:8508"
      - "8510:8510"
    volumes:
      - ./logs:/var/log/supervisor
      - redis_data:/var/lib/redis
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8508/health"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  redis_data:
EOF

# 5. Criar Dockerfile
echo "🔨 Criando Dockerfile..."
cat > Dockerfile << 'EOF'
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
EOF

# 6. Criar supervisord.conf
echo "⚙️ Criando supervisord.conf..."
cat > supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:redis]
command=redis-server --bind 127.0.0.1 --port 6379 --dir /var/lib/redis --save 60 1000 --appendonly yes
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/redis.log
stderr_logfile=/var/log/supervisor/redis.log
priority=100
user=redis

[program:fastapi]
command=python -m uvicorn api.main:app --host 0.0.0.0 --port 8508 --timeout-keep-alive 900
directory=/app
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/fastapi.log
stderr_logfile=/var/log/supervisor/fastapi.log
priority=200

[program:streamlit]
command=streamlit run admin_app/streamlit_admin.py --server.port 8510 --server.address 0.0.0.0 --server.headless true
directory=/app
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/streamlit.log
stderr_logfile=/var/log/supervisor/streamlit.log
priority=300
EOF

# 7. Criar start.sh
echo "🚀 Criando start.sh..."
cat > start.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Iniciando Suprema API (All-in-One)..."

mkdir -p /var/log/supervisor /var/lib/redis
chown redis:redis /var/lib/redis

echo "🔧 Iniciando supervisor..."
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &

echo "⏳ Aguardando Redis iniciar..."
for i in {1..30}; do
    if redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then
        echo "✅ Redis iniciado!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠️ Redis demorou para iniciar..."
    fi
    sleep 2
done

echo "⏳ Aguardando FastAPI..."
for i in {1..20}; do
    if curl -fsS http://127.0.0.1:8508/health >/dev/null 2>&1; then
        echo "✅ FastAPI iniciada!"
        break
    fi
    sleep 3
done

echo "🎉 Todos os serviços iniciados!"
echo "📊 Status:"
supervisorctl status

echo ""
echo "🌐 Acessos:"
echo "   API: http://localhost:8508"
echo "   Admin: http://localhost:8510"
echo ""

wait
EOF

chmod +x start.sh

# 8. Atualizar .env
echo "⚙️ Atualizando .env..."
if ! grep -q "REDIS_URL=redis://127.0.0.1:6379/0" .env 2>/dev/null; then
    echo "" >> .env
    echo "# Redis interno" >> .env
    echo "REDIS_URL=redis://127.0.0.1:6379/0" >> .env
fi

# 9. Build
echo "🔨 Fazendo build..."
docker build -t suprema-api:single . || {
    echo "❌ Erro no build!"
    echo "Verifique se todos os arquivos Python estão presentes."
    exit 1
}

# 10. Executar
echo "🚀 Iniciando container..."
docker-compose up -d

echo ""
echo "⏳ Aguardando serviços iniciarem (30s)..."
sleep 30

# 11. Verificar
echo ""
echo "🧪 Verificando serviços..."

echo -n "Redis: "
if docker exec suprema_allinone redis-cli ping >/dev/null 2>&1; then
    echo "✅"
else
    echo "❌"
fi

echo -n "FastAPI: "
if curl -fsS http://localhost:8508/health >/dev/null 2>&1; then
    echo "✅"
else
    echo "❌"
fi

echo -n "Streamlit: "
if curl -fsS http://localhost:8510 >/dev/null 2>&1; then
    echo "✅"
else
    echo "❌"
fi

echo ""
echo "🎉 Setup concluído!"
echo ""
echo "🌐 Acessos disponíveis:"
echo "   📊 API: http://localhost:8508"
echo "   📖 Docs: http://localhost:8508/docs"
echo "   ⚙️ Admin: http://localhost:8510"
echo ""
echo "🔧 Ver logs: docker-compose logs -f"
echo "🐛 Debug: docker exec -it suprema_allinone bash"
echo ""
echo "🧪 Teste rápido:"
echo "   curl http://localhost:8508/health"
echo ""

# Mostrar logs recentes
echo "📊 Logs recentes:"
echo "=================="
docker-compose logs --tail=15