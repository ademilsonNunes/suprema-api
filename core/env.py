# core/env.py
from pathlib import Path
from dotenv import load_dotenv, find_dotenv

def load_project_env() -> str | None:
    """
    Carrega o .env da raiz do projeto, independente do CWD.
    - 1º: tenta ../.env relativo a este arquivo
    - 2º: tenta .env na raiz do repo (subindo alguns níveis)
    - 3º: usa find_dotenv como fallback
    Retorna o path carregado (string) ou None.
    """
    here = Path(__file__).resolve()
    # candidata: raiz do repo = pai do diretório 'core'
    candidates = [
        here.parent.parent / ".env",   # <repo>/.env
        here.parent / ".env",          # <repo>/core/.env (raro)
    ]
    for p in candidates:
        if p.exists():
            load_dotenv(p, override=True)
            return str(p)

    # fallback: varre diretórios ascendentes a partir do CWD
    found = find_dotenv(usecwd=True)
    if found:
        load_dotenv(found, override=True)
        return found

    return None
