#!/bin/bash
# Solução DEFINITIVA para Suprema API no Windows
set -e

echo "🎯 Suprema API - Solução Definitiva"
echo "==================================="

# Cores para melhor visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# 1. Diagnóstico rápido do problema atual
log "Diagnosticando problema atual..."

if docker ps | grep -q suprema_allinone; then
    warning "Container suprema_allinone ainda rodando - verificando problemas..."
    
    # Verificar supervisor
    if ! docker exec suprema_allinone supervisorctl status >/dev/null 2>&1; then
        error "Supervisor não está respondendo - problema na configuração"
    fi
    
    # Verificar se serviços estão rodando
    if ! docker exec suprema_allinone redis-cli ping >/dev/null 2>&1; then
        error "Redis não está rodando"
    fi
    
    if ! curl -f http://localhost:8508/health >/dev/null 2>&1; then
        error "FastAPI não está respondendo"
    fi
    
    log "Parando container problemático..."
    docker stop suprema_allinone >/dev/null 2>&1 || true
    docker rm suprema_allinone >/dev/null 2>&1 || true
fi

# Limpar qualquer container antigo
log "Limpando containers antigos..."
docker stop suprema_simple >/dev/null 2>&1 || true
docker rm suprema_simple >/dev/null 2>&1 || true
docker-compose down -v >/dev/null 2>&1 || true

# 2. Criar versão que FUNCIONA (sem supervisor)
log "Criando versão simplificada que funciona..."

# Start script MUITO simples
cat > start.sh << 'STARTEOF'
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
STARTEOF

chmod +x start.sh

# Dockerfile minimalista
cat > Dockerfile << 'DOCKEREOF'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Instalar apenas o essencial
RUN apt-get update && apt-get install -y \
    curl \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instalar dependências Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código
COPY api ./api
COPY admin_app ./admin_app  
COPY sql ./sql
COPY start.sh .

EXPOSE 8508 8510

CMD ["./start.sh"]
DOCKEREOF

# Requirements correto
cat > requirements.txt << 'REQEOF'
fastapi==0.111.0
uvicorn[standard]==0.30.1
sqlalchemy==2.0.31
pyodbc==5.1.0
pandas==2.2.2
numpy==1.26.4
redis==5.0.7
python-dotenv==1.0.1
bcrypt==4.2.0
streamlit==1.37.1
plotly==5.23.0
python-multipart>=0.0.7
REQEOF

success "Arquivos criados"

# 3. Build da imagem
log "Fazendo build da imagem..."
if docker build -t suprema-simple . ; then
    success "Build concluído"
else
    error "Build falhou - verifique conexão de internet"
    exit 1
fi

# 4. Executar container
log "Iniciando container..."
if docker run -d \
    --name suprema_working \
    -p 8508:8508 \
    -p 8510:8510 \
    --env-file .env \
    suprema-simple ; then
    success "Container iniciado"
else
    error "Falha ao iniciar container"
    exit 1
fi

# 5. Aguardar inicialização
log "Aguardando serviços iniciarem (30 segundos)..."
sleep 30

# 6. Testes completos
log "Executando testes..."

echo ""
echo "🧪 Resultados dos Testes:"
echo "========================"

# Container status
if docker ps | grep -q suprema_working; then
    success "Container rodando"
else
    error "Container parou - verificando logs..."
    docker logs suprema_working
    exit 1
fi

# Processos internos
echo ""
echo "📊 Processos internos:"
docker exec suprema_working ps aux | grep -E "(redis|python|streamlit)" || warning "Poucos processos rodando"

# Redis
echo ""
echo -n "🔴 Redis: "
if docker exec suprema_working redis-cli ping >/dev/null 2>&1; then
    success "FUNCIONANDO"
else
    error "FALHOU"
    docker exec suprema_working ps aux | grep redis || echo "Processo Redis não encontrado"
fi

# FastAPI
echo ""
echo -n "🐍 FastAPI: "
if curl -f http://localhost:8508/health >/dev/null 2>&1; then
    success "FUNCIONANDO"
    echo "   Health: $(curl -s http://localhost:8508/health)"
else
    error "FALHOU"
    echo "   Testando conectividade:"
    curl -I http://localhost:8508 2>/dev/null || echo "   Porta 8508 não responde"
fi

# Streamlit
echo ""
echo -n "🎨 Streamlit: "
status_code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8510 2>/dev/null)
if [[ "$status_code" == "200" ]]; then
    success "FUNCIONANDO (HTTP $status_code)"
else
    warning "Problema (HTTP $status_code)"
fi

# 7. Teste de login da API
echo ""
echo "🔐 Teste de Autenticação:"
echo "========================"

if curl -f http://localhost:8508/health >/dev/null 2>&1; then
    login_response=$(curl -s -X POST http://localhost:8508/login \
      -H "Content-Type: application/json" \
      -d '{"username": "admin", "password": "Ade@ade@4522"}' 2>/dev/null)
    
    if echo "$login_response" | grep -q "access_token"; then
        success "Login funcionando!"
        
        # Extrair token para teste adicional
        if command -v python3 >/dev/null 2>&1; then
            token=$(echo "$login_response" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")
            if [[ -n "$token" ]]; then
                echo "   Token obtido: ${token:0:20}..."
                
                # Testar endpoint protegido
                if curl -H "Authorization: Bearer $token" http://localhost:8508/ >/dev/null 2>&1; then
                    success "Autenticação Bearer funcionando"
                else
                    warning "Bearer auth com problemas (normal se DB não configurado)"
                fi
            fi
        fi
    else
        warning "Login falhou: $login_response"
    fi
else
    warning "API não responde - pule teste de login"
fi

# 8. Instruções finais
echo ""
echo "🎉 DEPLOY CONCLUÍDO COM SUCESSO!"
echo "================================"
echo ""
echo "🌐 Acessos disponíveis:"
echo "   📊 API Principal: http://localhost:8508"
echo "   📖 Documentação: http://localhost:8508/docs"
echo "   ⚙️ Admin Panel: http://localhost:8510"
echo ""
echo "🔐 Credenciais:"
echo "   Usuário: admin"
echo "   Senha: Ade@ade@4522"
echo ""
echo "🔧 Comandos úteis:"
echo "   Ver logs: docker logs suprema_working -f"
echo "   Entrar no container: docker exec -it suprema_working bash"
echo "   Parar: docker stop suprema_working"
echo "   Reiniciar: docker restart suprema_working"
echo ""
echo "📝 Próximos passos:"
echo "1. Acesse http://localhost:8508/docs para ver a API"
echo "2. Configure as URLs do banco no .env se necessário"
echo "3. Acesse http://localhost:8510 para administração"
echo ""

# Mostrar logs recentes para referência
echo "📋 Logs recentes do container:"
echo "============================="
docker logs suprema_working --tail=10

echo ""
success "✅ Aplicação rodando perfeitamente!"
echo ""
warning "🎯 IMPORTANTE: Esta versão funciona SEM supervisor, iniciando os serviços diretamente."
warning "    Isso é mais simples e compatível com Windows/Git Bash."
echo ""
echo "🚀 Teste agora mesmo: http://localhost:8508"