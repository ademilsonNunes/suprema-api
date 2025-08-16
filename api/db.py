import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from .models import Base

DATABASE_URL = os.getenv("DATABASE_URL")
POLICY_DATABASE_URL = os.getenv("POLICY_DATABASE_URL")

# Engine de dados (Protheus_Producao)
data_engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args={"autocommit": True, "timeout": int(os.getenv("DB_CONNECTION_TIMEOUT", "300"))}
)

# Engine de políticas/logs (BISOBEL)
policy_engine = create_engine(
    POLICY_DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args={"autocommit": True, "timeout": int(os.getenv("DB_CONNECTION_TIMEOUT", "300"))}
)

PolicySessionLocal = sessionmaker(bind=policy_engine, autoflush=False, autocommit=False)

def init_policy_schema():
    Base.metadata.create_all(policy_engine)
