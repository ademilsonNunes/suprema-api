# 🛠️ Comandos de Desenvolvimento - Container Único

# === SETUP INICIAL ===
# Execute o script de setup completo
chmod +x setup_complete.sh
./setup_complete.sh

# === BUILD E EXECUÇÃO ===
# Build e executar
docker build -t suprema-api:single .
docker-compose up -d

# Rebuild completo
docker-compose down
docker build --no-cache -t suprema-api:single .
docker-compose up -d

# === MONITORAMENTO ===
# Ver logs em tempo real
docker-compose logs -f

# Logs por serviço
docker exec suprema_allinone tail -f /var/log/supervisor/fastapi.log
docker exec suprema_allinone tail -f /var/log/supervisor/streamlit.log
docker exec suprema_allinone tail -f /var/log/supervisor/redis.log

# Status dos serviços
docker exec suprema_allinone supervisorctl status

# === TESTES ===
# Health check
curl http://localhost:8508/health

# Login e obter token
TOKEN=$(curl -s -X POST http://localhost:8508/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "Ade@ade@4522"}' \
  | jq -r '.access_token')

echo "Token: $TOKEN"

# Testar endpoint com autenticação
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8508/carteira-logistica?limit=5"

# Testar rate limit (repetir várias vezes)
for i in {1..10}; do
  echo "Tentativa $i:"
  curl -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8508/faturamento-logistica?limit=1"
  sleep 1
done

# === REDIS OPERATIONS ===
# Conectar no Redis
docker exec -it suprema_allinone redis-cli

# Ver chaves de rate limit
docker exec suprema_allinone redis-cli KEYS "rl:*"

# Limpar rate limits
docker exec suprema_allinone redis-cli FLUSHDB

# Monitorar Redis em tempo real
docker exec suprema_allinone redis-cli MONITOR

# === DEBUG ===
# Entrar no container
docker exec -it suprema_allinone bash

# Ver processos rodando
docker exec suprema_allinone ps aux

# Verificar conectividade interna
docker exec suprema_allinone curl -fsS http://localhost:8508/health
docker exec suprema_allinone redis-cli ping

# Reiniciar serviços específicos
docker exec suprema_allinone supervisorctl restart fastapi
docker exec suprema_allinone supervisorctl restart streamlit
docker exec suprema_allinone supervisorctl restart redis

# === LIMPEZA ===
# Parar tudo
docker-compose down

# Remover volumes (CUIDADO - perde dados do Redis)
docker-compose down -v

# Limpar imagens antigas
docker image prune -f

# === BACKUP/RESTORE ===
# Backup do Redis
docker exec suprema_allinone redis-cli BGSAVE

# Backup das políticas (se DB estiver configurado)
docker exec suprema_allinone python -c "
from api.db import policy_engine
import pandas as pd
try:
    df = pd.read_sql('SELECT * FROM rate_limit_policy', policy_engine)
    df.to_csv('/tmp/policies_backup.csv', index=False)
    print('Backup salvo em /tmp/policies_backup.csv')
except Exception as e:
    print(f'Erro: {e}')
"

# === DEPLOY ===
# Tag para produção
docker tag suprema-api:single seunome/suprema-api:latest

# Push para Docker Hub
docker push seunome/suprema-api:latest

# Pull em produção
docker pull seunome/suprema-api:latest
docker-compose down && docker-compose up -d

# === VERIFICAÇÕES DE SAÚDE ===
# Script de verificação completa
check_health() {
    echo "🔍 Verificando saúde dos serviços..."
    
    echo -n "Container: "
    if docker ps | grep suprema_allinone >/dev/null; then
        echo "✅ Rodando"
    else
        echo "❌ Parado"
        return 1
    fi
    
    echo -n "Redis: "
    if docker exec suprema_allinone redis-cli ping >/dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ Falhou"
    fi
    
    echo -n "FastAPI: "
    if curl -fsS http://localhost:8508/health >/dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ Falhou"
    fi
    
    echo -n "Streamlit: "
    if curl -fsS http://localhost:8510 >/dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ Falhou"
    fi
    
    echo ""
    echo "📊 Status supervisor:"
    docker exec suprema_allinone supervisorctl status
}

# Executar verificação
# check_health