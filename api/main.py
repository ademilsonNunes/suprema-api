from fastapi import FastAPI, Depends, HTTPException, Security, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
from pydantic import BaseModel
import pandas as pd
import numpy as np
import os
import logging
from datetime import datetime, timedelta
from typing import Optional, Dict
from decimal import Decimal
import hashlib
import uuid

from .db import data_engine, init_policy_schema
from .rate_limiter import check_rate_limit

# Configuração de logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Timeouts
DB_CONNECTION_TIMEOUT = int(os.getenv("DB_CONNECTION_TIMEOUT", "300"))
DB_COMMAND_TIMEOUT    = int(os.getenv("DB_COMMAND_TIMEOUT", "600"))
POOL_TIMEOUT          = int(os.getenv("POOL_TIMEOUT", "300"))
HTTP_TIMEOUT          = int(os.getenv("HTTP_TIMEOUT", "900"))

# Base de usuários (exemplo; para produção, mover para DB)
USERS_DB = {
    "admin": {
        "password_hash": hashlib.sha256("Ade@ade@4522".encode()).hexdigest(),
        "role": "admin",
        "active": True
    },
    "logistica001": {
        "password_hash": hashlib.sha256("Suprema!@_2025#".encode()).hexdigest(),
        "role": "user",
        "active": True
    },
    "logistica002": {
        "password_hash": hashlib.sha256("Sobel!@_2025#".encode()).hexdigest(),
        "role": "user",
        "active": True
    }
}

ACTIVE_TOKENS: Dict[str, dict] = {}
security = HTTPBearer()

class LoginRequest(BaseModel):
    username: str
    password: str

class LoginResponse(BaseModel):
    access_token: str
    token_type: str
    role: str
    expires_at: str

app = FastAPI(
    title="Suprema API",
    description="API - fontes de dados homologadas",
    version="3.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def verify_password(password: str, password_hash: str) -> bool:
    return hash_password(password) == password_hash

def create_access_token(username: str, role: str) -> tuple:
    token = str(uuid.uuid4())
    expires_at = datetime.now() + timedelta(hours=24)
    ACTIVE_TOKENS[token] = {
        "username": username,
        "role": role,
        "expires_at": expires_at,
        "created_at": datetime.now()
    }
    return token, expires_at

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)) -> dict:
    token = credentials.credentials
    if token not in ACTIVE_TOKENS:
        raise HTTPException(status_code=401, detail="Token inválido ou expirado")
    token_data = ACTIVE_TOKENS[token]
    if datetime.now() > token_data["expires_at"]:
        del ACTIVE_TOKENS[token]
        raise HTTPException(status_code=401, detail="Token expirado")
    return token_data

@app.on_event("startup")
def on_startup():
    # Cria tabelas no BISOBEL se não existirem
    init_policy_schema()
    logger.info("Schema de políticas inicializado (BISOBEL).")

def get_current_user(request: Request, token_data: dict = Depends(verify_token)) -> dict:
    """Obtém usuário atual e aplica rate limit Redis + políticas do BISOBEL"""
    username = token_data["username"]
    role = token_data["role"]
    endpoint = request.url.path

    # Pula endpoints de sistema
    if endpoint in ["/", "/health", "/login", "/docs", "/openapi.json"]:
        return token_data

    try:
        check_rate_limit(username=username, role=role, endpoint=endpoint)
    except PermissionError as e:
        raise HTTPException(status_code=429, detail=str(e))
    return token_data

def get_db_connection_engine():
    return data_engine

def safe_convert_value(value):
    if value is None:
        return None
    elif pd.isna(value):
        return None
    elif isinstance(value, (np.integer, np.int64, np.int32)):
        return int(value)
    elif isinstance(value, (np.floating, np.float64, np.float32)):
        if np.isnan(value) or np.isinf(value):
            return None
        return float(value)
    elif isinstance(value, Decimal):
        return float(value)
    elif isinstance(value, (pd.Timestamp, datetime)):
        return value.isoformat()
    elif isinstance(value, bytes):
        try:
            return value.decode('utf-8')
        except UnicodeDecodeError:
            return str(value)
    elif isinstance(value, np.bool_):
        return bool(value)
    else:
        return value

def clean_dataframe_robust(df):
    import numpy as np
    cleaned_df = df.copy()
    numeric_cols = cleaned_df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 0:
        cleaned_df[numeric_cols] = cleaned_df[numeric_cols].replace([np.inf, -np.inf], np.nan)
    return cleaned_df, []

def convert_to_json_safe(df):
    records = []
    for _, row in df.iterrows():
        record = {}
        for col in df.columns:
            try:
                record[col] = safe_convert_value(row[col])
            except Exception:
                record[col] = None
        records.append(record)
    return records

def execute_table_query(table_name: str, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None):
    start_time = datetime.now()
    try:
        engine = get_db_connection_engine()
        query = f"SELECT * FROM {table_name}"
        if status_filter:
            query = f"SELECT * FROM ({query}) AS FILTERED WHERE STATUS = '{status_filter}'"
        if limit:
            query += f" OFFSET {offset} ROWS FETCH NEXT {limit} ROWS ONLY"

        with engine.connect() as conn:
            conn = conn.execution_options(autocommit=True)
            df = pd.read_sql(query, conn)

        cleaned_df, problematic_columns = clean_dataframe_robust(df)
        records = convert_to_json_safe(cleaned_df)
        exec_time = (datetime.now() - start_time).total_seconds()
        return {
            "success": True,
            "table": table_name,
            "data": records,
            "count": len(records),
            "execution_time": exec_time,
            "timestamp": datetime.now().isoformat(),
            "strategy_used": "robust_cleaning",
            "data_info": {
                "columns_count": len(df.columns),
                "problematic_columns": problematic_columns,
                "original_row_count": len(df)
            }
        }
    except SQLAlchemyError as e:
        exec_time = (datetime.now() - start_time).total_seconds()
        return {"success": False, "error": "Erro na consulta SQL", "details": str(e), "execution_time": exec_time}
    except Exception as e:
        exec_time = (datetime.now() - start_time).total_seconds()
        return {"success": False, "error": "Erro interno", "details": str(e), "execution_time": exec_time}

@app.post("/login", response_model=LoginResponse)
async def login(login_data: LoginRequest):
    username = login_data.username
    password = login_data.password
    if username not in USERS_DB:
        raise HTTPException(status_code=401, detail="Usuário ou senha inválidos")
    user = USERS_DB[username]
    if not user["active"]:
        raise HTTPException(status_code=401, detail="Usuário inativo")
    if not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Usuário ou senha inválidos")
    token, expires_at = create_access_token(username, user["role"])
    return LoginResponse(access_token=token, token_type="bearer", role=user["role"], expires_at=expires_at.isoformat())

@app.get("/")
async def root():
    return {
        "message": "Suprema - API Logística",
        "status": "online",
        "version": "3.0.0",
        "authentication": {"required": True, "login_endpoint": "/login", "token_type": "Bearer"},
        "rate_limits": {
            "backing_store": "redis",
            "policies": "BISOBEL",
            "logs": "BISOBEL",
        },
        "admin_app": "Streamlit (/admin externo)",
        "endpoints": [
            "/carteira-logistica", "/mov-estoque-logistica", "/docas-logistica",
            "/pedidos-romaneio-logistica", "/carregamento-logistica", "/faturamento-logistica"
        ]
    }

@app.get("/health")
async def health():
    try:
        with data_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "healthy"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.get("/carteira-logistica")
async def get_carteira_logistica(request: Request, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    return execute_table_query("CARTEIRA_LOGISTICA", limit, offset, status_filter)

@app.get("/mov-estoque-logistica")
async def get_mov_estoque_logistica(request: Request, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    return execute_table_query("MOV_ESTOQUE_LOGISTICA", limit, offset, status_filter)

@app.get("/docas-logistica")
async def get_docas_logistica(request: Request, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    return execute_table_query("DOCAS_LOGISTICA", limit, offset, status_filter)

@app.get("/pedidos-romaneio-logistica")
async def get_pedidos_romaneio_logistica(request: Request, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    return execute_table_query("PEDIDOS_ROMANEIO_LOGISTICA", limit, offset, status_filter)

@app.get("/carregamento-logistica")
async def get_carregamento_logistica(request: Request, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    return execute_table_query("CARREGAMENTO_LOGISTICA", limit, offset, status_filter)

@app.get("/faturamento-logistica")
async def get_faturamento_logistica(request: Request, limit: Optional[int] = None, offset: Optional[int] = 0, status_filter: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    return execute_table_query("FATURAMENTO_LOGISTICA", limit, offset, status_filter)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8508, timeout_keep_alive=HTTP_TIMEOUT, timeout_graceful_shutdown=30, access_log=True, log_level="info")
