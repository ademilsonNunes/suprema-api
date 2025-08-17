#!/bin/bash
# Script para diagnosticar e corrigir problemas de login do Admin Panel
set -e

echo "🔍 Diagnóstico do Login Admin (Streamlit)"
echo "========================================="

# Verificar se container está rodando
CONTAINER_NAME=""
if docker ps | grep -q suprema_working; then
    CONTAINER_NAME="suprema_working"
elif docker ps | grep -q suprema_final; then
    CONTAINER_NAME="suprema_final"
elif docker ps | grep -q myapp; then
    CONTAINER_NAME="myapp"
elif docker ps | grep -q suprema_test; then
    CONTAINER_NAME="suprema_test"
else
    echo "❌ Nenhum container da aplicação encontrado rodando"
    echo "Execute primeiro o script de deploy da aplicação"
    exit 1
fi

echo "✅ Container encontrado: $CONTAINER_NAME"
echo ""

# 1. Verificar conectividade com banco BISOBEL
echo "PASSO 1: Testando conexão com banco BISOBEL"
echo "==========================================="

docker exec $CONTAINER_NAME python -c "
import os
from sqlalchemy import create_engine, text

try:
    # Testar conexão com banco de políticas
    policy_url = os.getenv('POLICY_DATABASE_URL')
    print('URL do banco BISOBEL:', policy_url)
    
    engine = create_engine(policy_url, pool_pre_ping=True)
    with engine.connect() as conn:
        result = conn.execute(text('SELECT 1 as test'))
        print('✅ Conexão com BISOBEL: OK')
        
except Exception as e:
    print('❌ Erro de conexão com BISOBEL:', str(e))
    exit(1)
" || {
    echo ""
    echo "❌ PROBLEMA: Não consegue conectar no banco BISOBEL"
    echo ""
    echo "💡 Soluções:"
    echo "1. Verifique se o SQL Server está rodando"
    echo "2. Verifique as URLs no .env:"
    echo "   POLICY_DATABASE_URL=mssql+pyodbc://..."
    echo "3. Teste a conexão manualmente"
    exit 1
}

echo ""

# 2. Verificar se tabela admin_user existe
echo "PASSO 2: Verificando estrutura do banco"
echo "======================================="

docker exec $CONTAINER_NAME python -c "
import os
from sqlalchemy import create_engine, text

try:
    policy_url = os.getenv('POLICY_DATABASE_URL')
    engine = create_engine(policy_url, pool_pre_ping=True)
    
    with engine.connect() as conn:
        # Verificar se tabela existe
        result = conn.execute(text(\"\"\"
            SELECT COUNT(*) as table_exists 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_NAME = 'admin_user'
        \"\"\")).fetchone()
        
        if result[0] > 0:
            print('✅ Tabela admin_user existe')
            
            # Ver quantos usuários existem
            result = conn.execute(text('SELECT COUNT(*) FROM dbo.admin_user')).fetchone()
            print(f'📊 Usuários na tabela: {result[0]}')
            
            # Listar usuários
            result = conn.execute(text('SELECT username, active, created_at FROM dbo.admin_user')).fetchall()
            print('👥 Usuários encontrados:')
            for row in result:
                status = '✅ Ativo' if row[1] else '❌ Inativo'
                print(f'   - {row[0]} ({status}) - Criado: {row[2]}')
                
        else:
            print('❌ Tabela admin_user NÃO existe')
            print('🔧 Será criada automaticamente...')
            
except Exception as e:
    print('❌ Erro ao verificar tabela:', str(e))
" || echo "Erro ao verificar estrutura do banco"

echo ""

# 3. Criar/Verificar usuário admin
echo "PASSO 3: Criando/Verificando usuário admin"
echo "=========================================="

docker exec $CONTAINER_NAME python -c "
import os
import bcrypt
from sqlalchemy import create_engine, text

try:
    policy_url = os.getenv('POLICY_DATABASE_URL')
    engine = create_engine(policy_url, pool_pre_ping=True)
    
    # Gerar hash para 'Admin@123'
    password = 'Admin@123'
    salt = bcrypt.gensalt(rounds=12)
    password_hash = bcrypt.hashpw(password.encode(), salt).decode()
    
    print(f'🔐 Gerando hash para senha: {password}')
    print(f'📝 Hash gerado: {password_hash[:50]}...')
    
    with engine.begin() as conn:
        # Criar tabela se não existir
        conn.execute(text(\"\"\"
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'admin_user')
            BEGIN
              CREATE TABLE dbo.admin_user (
                id INT IDENTITY PRIMARY KEY,
                username NVARCHAR(100) NOT NULL UNIQUE,
                password_hash NVARCHAR(255) NOT NULL,
                role NVARCHAR(50) NOT NULL DEFAULT 'admin',
                active BIT NOT NULL DEFAULT 1,
                created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
              );
            END;
        \"\"\"))
        
        # Verificar se admin já existe
        result = conn.execute(text('SELECT COUNT(*) FROM dbo.admin_user WHERE username = :u'), {'u': 'admin'}).fetchone()
        
        if result[0] > 0:
            print('👤 Usuário admin já existe - atualizando senha...')
            conn.execute(text(\"\"\"
                UPDATE dbo.admin_user 
                SET password_hash = :hash, active = 1 
                WHERE username = 'admin'
            \"\"\"), {'hash': password_hash})
        else:
            print('👤 Criando usuário admin...')
            conn.execute(text(\"\"\"
                INSERT INTO dbo.admin_user (username, password_hash, role, active)
                VALUES ('admin', :hash, 'admin', 1)
            \"\"\"), {'hash': password_hash})
        
        print('✅ Usuário admin configurado com sucesso!')
        
        # Verificar se foi criado corretamente
        result = conn.execute(text('SELECT username, active FROM dbo.admin_user WHERE username = :u'), {'u': 'admin'}).fetchone()
        if result:
            status = 'Ativo' if result[1] else 'Inativo'
            print(f'✅ Verificação: {result[0]} está {status}')
        
except Exception as e:
    print('❌ Erro ao configurar usuário:', str(e))
    import traceback
    traceback.print_exc()
"

echo ""

# 4. Testar autenticação
echo "PASSO 4: Testando autenticação"
echo "=============================="

docker exec $CONTAINER_NAME python -c "
import os
import bcrypt
from sqlalchemy import create_engine, text

def test_auth(username, password):
    try:
        policy_url = os.getenv('POLICY_DATABASE_URL')
        engine = create_engine(policy_url, pool_pre_ping=True)
        
        with engine.connect() as conn:
            result = conn.execute(text('SELECT password_hash, active FROM dbo.admin_user WHERE username = :u'), {'u': username}).fetchone()
            
            if not result:
                print(f'❌ Usuário {username} não encontrado')
                return False
                
            stored_hash = result[0]
            active = result[1]
            
            if not active:
                print(f'❌ Usuário {username} está inativo')
                return False
                
            # Converter hash para bytes se necessário
            if isinstance(stored_hash, str):
                stored_hash = stored_hash.encode()
                
            # Verificar senha
            if bcrypt.checkpw(password.encode(), stored_hash):
                print(f'✅ Autenticação OK para {username}')
                return True
            else:
                print(f'❌ Senha incorreta para {username}')
                return False
                
    except Exception as e:
        print(f'❌ Erro na autenticação: {str(e)}')
        return False

# Testar com credenciais
print('🔐 Testando login: admin / Admin@123')
if test_auth('admin', 'Admin@123'):
    print('✅ SUCESSO: As credenciais funcionam!')
else:
    print('❌ FALHA: Problema na autenticação')
"

echo ""

# 5. Verificar Streamlit
echo "PASSO 5: Verificando Streamlit Admin"
echo "===================================="

echo "🎨 Status do Streamlit:"
if curl -s http://localhost:8510 >/dev/null 2>&1; then
    echo "✅ Streamlit acessível em http://localhost:8510"
else
    echo "❌ Streamlit não está respondendo"
    echo "Verificando logs do Streamlit..."
    docker logs $CONTAINER_NAME 2>&1 | grep -i streamlit | tail -5
fi

echo ""

# 6. Instruções finais
echo "RESULTADO FINAL"
echo "==============="
echo ""
echo "🌐 Admin Panel: http://localhost:8510"
echo "🔐 Credenciais:"
echo "   Usuário: admin"
echo "   Senha: Admin@123"
echo ""
echo "💡 Se ainda não funcionar:"
echo "1. Reinicie o container: docker restart $CONTAINER_NAME"
echo "2. Aguarde 30 segundos e tente novamente"
echo "3. Verifique se a porta 8510 não está bloqueada"
echo ""

# 7. Gerar hash adicional para referência
echo "INFORMAÇÕES ADICIONAIS"
echo "====================="
echo ""
echo "🔧 Para gerar novos hashes de senha:"

docker exec $CONTAINER_NAME python -c "
import bcrypt

def generate_hash(password):
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode(), salt).decode()

print('📝 Hashes para senhas comuns:')
passwords = ['Admin@123', 'admin123', '123456', 'password']
for pwd in passwords:
    hash_val = generate_hash(pwd)
    print(f'   {pwd} -> {hash_val}')
"

echo ""
echo "✅ Diagnóstico concluído!"
echo ""
echo "🚀 Tente acessar: http://localhost:8510"
echo "   Usuário: admin"
echo "   Senha: Admin@123"