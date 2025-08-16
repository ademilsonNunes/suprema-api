#!/bin/bash
set -e

echo "🚀 Iniciando Suprema API (Método Direto)..."

# Criar diretórios e permissões
mkdir -p /var/log/supervisor /var/lib/redis /var/log/redis
chown redis:redis /var/lib/redis /var/log/redis

# Iniciar Redis DIRETAMENTE (não via supervisor)
echo "🔴 Iniciando Redis diretamente..."
redis-server --daemonize yes \
    --bind 127.0.0.1 \
    --port 6379 \
    --dir /var/lib/redis \
    --save 60 1000 \
    --logfile /var/log/redis/redis.log \
    --pidfile /var/run/redis.pid

# Aguardar Redis ficar pronto
echo "⏳ Aguardando Redis..."
for i in {1..20}; do
    if redis-cli ping >/dev/null 2>&1; then
        echo "✅ Redis OK!"
        break
    fi
    if [ $i -eq 20 ]; then
        echo "❌ Redis falhou após 20 tentativas"
        echo "🔍 Verificando logs..."
        cat /var/log/redis/redis.log || echo "Sem log do Redis"
        echo "⚠️ Continuando sem Redis (rate limiting desabilitado)"
        export USER_RATE_LIMIT_ENABLED=false
    fi
    sleep 1
done

# Agora iniciar supervisor SEM Redis (já está rodando)
echo "🔧 Iniciando FastAPI e Streamlit via supervisor..."

# Criar supervisord.conf temporário SEM Redis
cat > /tmp/supervisord_no_redis.conf << 'SUPERVISOR_EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:fastapi]
command=python -m uvicorn api.main:app --host 0.0.0.0 --port 8508 --timeout-keep-alive 900
directory=/app
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/fastapi.log
stderr_logfile=/var/log/supervisor/fastapi.log

[program:streamlit]
command=streamlit run admin_app/streamlit_admin.py --server.port 8510 --server.address 0.0.0.0 --server.headless true
directory=/app
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/streamlit.log
stderr_logfile=/var/log/supervisor/streamlit.log
SUPERVISOR_EOF

# Executar supervisor
exec /usr/bin/supervisord -c /tmp/supervisord_no_redis.conf