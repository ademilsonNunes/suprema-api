# 🚀 Suprema API - Tutorial Completo

## 📁 Estrutura Final do Projeto

```
suprema-api/
├── .env
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── supervisord.conf          # ← NOVO
├── start.sh                  # ← NOVO
├── api/
│   ├── __init__.py          # ← NOVO
│   ├── main.py
│   ├── db.py
│   ├── models.py
│   └── rate_limiter.py
├── admin_app/
│   └── streamlit_admin.py   # ← CORRIGIDO
└── sql/
    └── schema.sql
```

## 🏠 Teste Local com Docker

### 1. Preparação dos Arquivos

Crie os arquivos que estavam faltando:

**supervisord.conf** (raiz do projeto)
```bash
# Ver artifact acima
```

**start.sh** (raiz do projeto)
```bash
# Ver artifact acima
chmod +x start.sh
```

**api/__init__.py**
```python
# API Package
```

### 2. Configuração do Ambiente

Ajuste o `.env` para teste local:

```bash
# Para teste local, use bancos de desenvolvimento
DATABASE_URL=mssql+pyodbc://sa:SuaSenga@localhost:1433/TestDB?driver=ODBC+Driver+18+for+SQL+Server
POLICY_DATABASE_URL=mssql+pyodbc://sa:SuaSenga@localhost:1433/TestDB?driver=ODBC+Driver+18+for+SQL+Server

REDIS_URL=redis://127.0.0.1:6379/0
USER_RATE_LIMIT_ENABLED=true
USER_RATE_LIMIT_WINDOW_SEC=60
USER_RATE_LIMIT_BLOCK_SEC=300
USER_RATE_LIMIT_MAX_CALLS=5
RATE_LIMIT_ALGO=sliding
RATE_EVENT_SAMPLING=1.0
ADMIN_APP_SECRET=mude_isto_local
```

### 3. Build e Execução Local

```bash
# Build da imagem
docker build -t suprema-api:local .

# Executar com docker-compose
docker-compose up -d

# Verificar logs
docker-compose logs -f

# Verificar status
curl http://localhost:8508/health
```

### 4. Testes da API

```bash
# 1. Login
curl -X POST http://localhost:8508/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "Ade@ade@4522"}'

# 2. Usar o token (substitua TOKEN)
curl -H "Authorization: Bearer TOKEN" \
  http://localhost:8508/carteira-logistica

# 3. Testar rate limit (múltiplas calls)
for i in {1..10}; do
  curl -H "Authorization: Bearer TOKEN" \
    http://localhost:8508/carteira-logistica
done
```

### 5. Acessar Admin

- **Streamlit Admin**: http://localhost:8510
- **API Docs**: http://localhost:8508/docs

---

## 🌐 Deploy com Docker Hub

### 1. Preparar para Produção

Atualize o `.env` para produção:

```bash
# URLs de produção
DATABASE_URL=mssql+pyodbc://sa:SenhaReal@servidor:1433/Protheus_Producao?driver=ODBC+Driver+18+for+SQL+Server
POLICY_DATABASE_URL=mssql+pyodbc://sa:SenhaReal@servidor:1433/BISOBEL?driver=ODBC+Driver+18+for+SQL+Server

# Rate limits de produção
USER_RATE_LIMIT_WINDOW_SEC=3600
USER_RATE_LIMIT_MAX_CALLS=1
USER_RATE_LIMIT_BLOCK_SEC=10800

# Segurança
ADMIN_APP_SECRET=seu_secret_forte_aqui_$(openssl rand -hex 32)
```

### 2. Build e Push para Docker Hub

```bash
# Login no Docker Hub
docker login

# Build para produção
docker build -t seunome/suprema-api:latest .

# Tag adicional com versão
docker tag seunome/suprema-api:latest seunome/suprema-api:v1.0.0

# Push para o hub
docker push seunome/suprema-api:latest
docker push seunome/suprema-api:v1.0.0
```

### 3. Deploy no Servidor

**No servidor de produção**, crie um `docker-compose.prod.yml`:

```yaml
services:
  suprema:
    image: seunome/suprema-api:latest
    container_name: suprema_prod
    restart: unless-stopped
    env_file: .env
    ports:
      - "8508:8508"
      - "8510:8510"
    volumes:
      - ./logs:/var/log/supervisor
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8508/health"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
    environment:
      - TZ=America/Sao_Paulo
```

### 4. Executar Deploy

```bash
# No servidor, crie o diretório
mkdir -p /opt/suprema-api
cd /opt/suprema-api

# Copie o .env de produção
# Configure as URLs reais dos bancos

# Pull e start
docker pull seunome/suprema-api:latest
docker-compose -f docker-compose.prod.yml up -d

# Verificar
docker-compose -f docker-compose.prod.yml logs -f
curl http://localhost:8508/health
```

### 5. Configuração do Proxy Reverso (Nginx)

```nginx
# /etc/nginx/sites-available/suprema-api
server {
    listen 80;
    server_name api.suaempresa.com;

    location / {
        proxy_pass http://127.0.0.1:8508;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 900s;
    }
}

server {
    listen 80;
    server_name admin.suaempresa.com;

    location / {
        proxy_pass http://127.0.0.1:8510;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 900s;
    }
}
```

---

## 🔧 Comandos Úteis de Manutenção

### Atualizar Deploy

```bash
# Pull nova versão
docker pull seunome/suprema-api:latest

# Restart com zero downtime
docker-compose -f docker-compose.prod.yml up -d --force-recreate

# Limpar imagens antigas
docker image prune -f
```

### Logs e Monitoramento

```bash
# Logs em tempo real
docker-compose logs -f suprema

# Logs específicos
docker exec suprema_prod tail -f /var/log/supervisor/fastapi.log
docker exec suprema_prod tail -f /var/log/supervisor/streamlit.log

# Status dos serviços
docker exec suprema_prod supervisorctl status
```

### Backup do Redis

```bash
# Backup manual
docker exec suprema_prod redis-cli BGSAVE

# Restaurar (se necessário)
docker exec suprema_prod redis-cli FLUSHALL
```

---

## 🛡️ Checklist de Segurança

- [ ] Alterar senhas default no código
- [ ] Configurar firewall (portas 8508, 8510)
- [ ] Usar HTTPS em produção
- [ ] Configurar backup do banco BISOBEL
- [ ] Monitorar logs de rate limit
- [ ] Implementar log rotation
- [ ] Configurar alertas de uptime

---

## 📝 Próximos Passos

1. **SSL/HTTPS**: Configure certificados Let's Encrypt
2. **Monitoramento**: Adicione Prometheus + Grafana
3. **Backup**: Automatize backup das tabelas de política
4. **CI/CD**: Configure pipeline GitHub Actions
5. **Observabilidade**: Adicione métricas de performance