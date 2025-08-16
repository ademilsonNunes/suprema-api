import os
import time
import bcrypt
import pandas as pd
import plotly.express as px
import streamlit as st
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from datetime import datetime, timedelta

# ENV
POLICY_DATABASE_URL = os.getenv("POLICY_DATABASE_URL")
ADMIN_APP_SECRET = os.getenv("ADMIN_APP_SECRET", "change_me_for_streamlit_csrf")

# DB
engine = create_engine(POLICY_DATABASE_URL, pool_pre_ping=True, pool_recycle=3600)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

st.set_page_config(page_title="Admin - Rate Limit", page_icon="🔐", layout="wide")

def auth_user(username: str, password: str) -> bool:
    with engine.connect() as conn:
        row = conn.execute(text("SELECT password_hash, active FROM dbo.admin_user WHERE username=:u"), {"u": username}).fetchone()
        if not row:
            return False
        hash_bytes = row[0].encode() if isinstance(row[0], str) else row[0]
        active = bool(row[1])
        if not active:
            return False
        return bcrypt.checkpw(password.encode(), hash_bytes)

def ensure_session():
    if "auth" not in st.session_state:
        st.session_state.auth = False
    if "user" not in st.session_state:
        st.session_state.user = None

def login_form():
    st.title("🔐 Administração - Rate Limit")
    st.caption("BISOBEL • Políticas, bloqueios e relatórios")
    with st.form("login"):
        u = st.text_input("Usuário", placeholder="admin")
        p = st.text_input("Senha", type="password")
        submitted = st.form_submit_button("Entrar")
    if submitted:
        if auth_user(u, p):
            st.session_state.auth = True
            st.session_state.user = u
            st.success("Login efetuado.")
            st.experimental_rerun()
        else:
            st.error("Credenciais inválidas.")

def top_nav():
    st.sidebar.title("Admin")
    st.sidebar.write(f"Usuário: **{st.session_state.user}**")
    page = st.sidebar.radio("Menu", ["Políticas", "Bloqueios", "Relatórios", "Utilitários"])
    if st.sidebar.button("Sair"):
        st.session_state.clear()
        st.experimental_rerun()
    return page

def page_policies():
    st.header("⚙️ Políticas de Rate Limit")
    st.caption("Ordem por prioridade (maior primeiro). Níveis: global, role, user, endpoint, user_endpoint, role_endpoint")

    # Listagem
    with engine.connect() as conn:
        df = pd.read_sql("SELECT * FROM dbo.rate_limit_policy ORDER BY enabled DESC, priority DESC, updated_at DESC", conn)

    st.dataframe(df, use_container_width=True, height=350)

    with st.expander("➕ Nova política"):
        with st.form("new_policy"):
            level = st.selectbox("level", ["global", "role", "user", "endpoint", "user_endpoint", "role_endpoint"])
            role = st.text_input("role (opcional)")
            username = st.text_input("username (opcional)")
            endpoint = st.text_input("endpoint (opcional)", placeholder="/faturamento-logistica")
            window_sec = st.number_input("window_sec", min_value=1, value=3600)
            max_calls = st.number_input("max_calls", min_value=1, value=1)
            block_sec = st.number_input("block_sec", min_value=1, value=10800)
            enabled = st.checkbox("enabled", value=True)
            priority = st.number_input("priority (maior ganha)", min_value=0, value=10)
            notes = st.text_area("notes", "")
            submitted = st.form_submit_button("Salvar")
        if submitted:
            with engine.begin() as conn:
                conn.execute(text("""
                    INSERT INTO dbo.rate_limit_policy(level, role, username, endpoint, window_sec, max_calls, block_sec, enabled, priority, notes, created_by, updated_at)
                    VALUES (:level, :role, :username, :endpoint, :window_sec, :max_calls, :block_sec, :enabled, :priority, :notes, :by, SYSUTCDATETIME())
                """), dict(level=level, role=role or None, username=username or None, endpoint=endpoint or None,
                           window_sec=int(window_sec), max_calls=int(max_calls), block_sec=int(block_sec),
                           enabled=1 if enabled else 0, priority=int(priority), notes=notes or None, by=st.session_state.user))
            st.success("Política criada.")
            st.experimental_rerun()

    with st.expander("✏️ Editar/Desativar política"):
        pid = st.number_input("ID da política", min_value=1)
        col1, col2 = st.columns(2)
        with col1:
            new_enabled = st.selectbox("enabled", [True, False])
            new_priority = st.number_input("priority", min_value=0, value=10)
        with col2:
            new_window = st.number_input("window_sec", min_value=1, value=3600)
            new_max = st.number_input("max_calls", min_value=1, value=1)
            new_block = st.number_input("block_sec", min_value=1, value=10800)
        notes = st.text_area("notes (opcional)")
        if st.button("Atualizar"):
            with engine.begin() as conn:
                res = conn.execute(text("""
                    UPDATE dbo.rate_limit_policy
                    SET enabled=:en, priority=:pr, window_sec=:ws, max_calls=:mc, block_sec=:bs, notes=:nt, updated_at=SYSUTCDATETIME()
                    WHERE id=:id
                """), dict(en=1 if new_enabled else 0, pr=int(new_priority),
                           ws=int(new_window), mc=int(new_max), bs=int(new_block),
                           nt=notes or None, id=int(pid)))
            st.success("Atualizado.")
            st.experimental_rerun()

def page_blocks():
    st.header("⛔ Bloqueios manuais")
    with engine.connect() as conn:
        df = pd.read_sql("""
            SELECT TOP 500 * FROM dbo.rate_limit_block ORDER BY cleared_at ASC, block_until DESC
        """, conn)
    st.dataframe(df, use_container_width=True, height=350)

    with st.expander("➕ Novo bloqueio"):
        with st.form("new_block"):
            username = st.text_input("username", "")
            endpoint = st.text_input("endpoint", "")
            minutes = st.number_input("duração (min)", min_value=1, value=60)
            reason = st.text_input("reason", "manual")
            submitted = st.form_submit_button("Bloquear")
        if submitted:
            until = datetime.utcnow() + timedelta(minutes=int(minutes))
            with engine.begin() as conn:
                conn.execute(text("""
                    INSERT INTO dbo.rate_limit_block(username, endpoint, block_until, reason, created_by, created_at)
                    VALUES (:u, :e, :until, :r, :by, SYSUTCDATETIME())
                """), dict(u=username, e=endpoint, until=until, r=reason, by=st.session_state.user))
            st.success("Bloqueio registrado.")
            st.experimental_rerun()

    with st.expander("🔓 Desbloquear"):
        bid = st.number_input("ID do bloqueio", min_value=1)
        if st.button("Desbloquear"):
            with engine.begin() as conn:
                conn.execute(text("""
                    UPDATE dbo.rate_limit_block
                    SET cleared_at=SYSUTCDATETIME(), cleared_by=:by
                    WHERE id=:id AND cleared_at IS NULL
                """), dict(by=st.session_state.user, id=int(bid)))
            st.success("Desbloqueado (DB). Se houver chave no Redis, expirará automaticamente pelo TTL.")

def page_reports():
    st.header("📈 Relatórios & Indicadores")
    days = st.slider("Período (dias)", 1, 30, 7)
    since = datetime.utcnow() - timedelta(days=days)
    with engine.connect() as conn:
        df = pd.read_sql(text("""
            SELECT ts, username, role, endpoint, decision, calls
            FROM dbo.rate_limit_event
            WHERE ts >= :since
            ORDER BY ts DESC
        """), conn, params={"since": since})
    if df.empty:
        st.info("Sem eventos no período.")
        return
    c1, c2, c3 = st.columns(3)
    c1.metric("Total eventos", len(df))
    c2.metric("Blocks", (df["decision"] == "block").sum())
    c3.metric("Allow", (df["decision"] == "allow").sum())

    fig = px.histogram(df, x="endpoint", color="decision", barmode="group", title="Eventos por endpoint")
    st.plotly_chart(fig, use_container_width=True)

    df["date"] = pd.to_datetime(df["ts"]).dt.date
    agg = df.groupby(["date", "decision"]).size().reset_index(name="count")
    fig2 = px.line(agg, x="date", y="count", color="decision", title="Eventos por dia")
    st.plotly_chart(fig2, use_container_width=True)

    with st.expander("🔎 Filtro detalhado"):
        user = st.text_input("username (opcional)")
        endpoint = st.text_input("endpoint (opcional)")
        q = "SELECT TOP 1000 * FROM dbo.rate_limit_event WHERE ts >= :since"
        params = {"since": since}
        if user:
            q += " AND username = :u"
            params["u"] = user
        if endpoint:
            q += " AND endpoint = :e"
            params["e"] = endpoint
        q += " ORDER BY ts DESC"
        with engine.connect() as conn:
            df2 = pd.read_sql(text(q), conn, params=params)
        st.dataframe(df2, use_container_width=True, height=300)

def page_utils():
    st.header("🔧 Utilitários")
    st.subheader("Gerar hash (bcrypt) para senha admin")
    pwd = st.text_input("Senha para hash", type="password")
    if st.button("Gerar hash"):
        if not pwd:
            st.warning("Informe uma senha.")
        else:
            salt = bcrypt.gensalt(rounds=12)
            h = bcrypt.hashpw(pwd.encode(), salt).decode()
            st.code(h, language="text")
            st.success("Copie e atualize na tabela dbo.admin_user.password_hash")

def main():
    st.session_state.setdefault("csrf", ADMIN_APP_SECRET)
    ensure_session()
    if not st.session_state.auth:
        login_form()
        return
    page = top_nav()
    if page == "Políticas":
        page_policies()
    elif page == "Bloqueios":
        page_blocks()
    elif page == "Relatórios":
        page_reports()
    else:
        page_utils()

if __name__ == "__main__":
    main()
