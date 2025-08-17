#!/bin/bash
set -e
echo "🚀 Suprema API - Iniciando..."

# Configurar diretórios
mkdir -p /var/lib/redis /var/log
chmod 755 /var/lib/redis

# Iniciar Redis em background
echo "🔴 Iniciando Redis..."
redis-server --daemonize yes --bind 127.0.0.1 --port 6379 &
sleep 3

# Verificar Redis
redis-cli ping || echo "⚠️ Redis com problemas"

# Iniciar FastAPI
echo "🐍 Iniciando FastAPI..."
cd /app
python -m uvicorn api.main:app --host 0.0.0.0 --port 8508 --log-level info &
sleep 5

# Iniciar Streamlit  
echo "🎨 Iniciando Streamlit..."
streamlit run admin_app/streamlit_admin.py --server.port 8510 --server.address 0.0.0.0 --server.headless true &

echo "✅ Serviços iniciados!"
echo "📊 API: http://localhost:8508"
echo "📊 Admin: http://localhost:8510"

# Manter container vivo
tail -f /dev/null
