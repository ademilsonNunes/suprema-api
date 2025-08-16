# ✅ Checklist Final - Container Único Redis

## 📁 Arquivos para Substituir/Criar

### 1. **docker-compose.yml** (SUBSTITUIR)
```yaml
# Usar o conteúdo do artifact "docker-compose.yml (Container Único)"
```

### 2. **Dockerfile** (SUBSTITUIR)
```dockerfile
# Usar o conteúdo do artifact "Dockerfile (Redis Interno Corrigido)"
```

### 3. **supervisord.conf** (CRIAR/SUBSTITUIR)
```bash
# Usar o conteúdo do artifact "supervisord.conf (Redis Interno)"
```

### 4. **start.sh** (CRIAR/SUBSTITUIR)
```bash
# Usar o conteúdo do artifact "start.sh (Container Único)"
chmod +x start.sh
```

### 5. **api/__init__.py** (CRIAR se não existir)
```python
# API Package
```

### 6. **setup_complete.sh** (CRIAR - Opcional)
```bash
# Script de setup automático (artifact "setup_complete.sh")
chmod +x setup_complete.sh
```

## 🚀 Comandos para Executar

### Passo 1: Aplicar Correções
```bash
# 1. Criar arquivos faltantes
echo "# API Package" > api/__init__.py

# 2. Garantir permissões
chmod +x start.sh
chmod +x setup_complete.sh  # se criou

# 3. Criar diretório de logs
mkdir -p logs
```

### Passo 2: Build e Teste
```bash
# 1. Parar containers existentes
docker-compose down

# 2. Build
docker build -t suprema-api:single .

# 3. Executar
docker-compose up -d

# 4. Ver logs
docker-compose logs -f
```

### Passo 3: Verificar Funcionamento
```bash
# 1. Aguardar 30 segundos para serviços iniciarem
sleep 30

# 2. Testar Redis
docker exec suprema_allinone redis-cli ping

# 3. Testar API
curl http://localhost:8508/health

# 4. Ver status dos serviços
docker exec suprema_allin