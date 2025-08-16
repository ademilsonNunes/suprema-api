import os, time, random
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from redis import Redis
from sqlalchemy import select, and_, or_, desc
from .db import PolicySessionLocal
from .models import RateLimitPolicy, RateLimitEvent, RateLimitBlock

# Redis
redis_client = Redis.from_url(os.getenv("REDIS_URL", "redis://localhost:6379/0"), decode_responses=True)

# Fallbacks (ENV)
FALLBACK_ENABLED = os.getenv("USER_RATE_LIMIT_ENABLED", "true").lower() == "true"
FALLBACK_WINDOW = int(os.getenv("USER_RATE_LIMIT_WINDOW_SEC", "3600"))
FALLBACK_BLOCK  = int(os.getenv("USER_RATE_LIMIT_BLOCK_SEC", "10800"))
FALLBACK_MAX    = int(os.getenv("USER_RATE_LIMIT_MAX_CALLS", "1"))
EVENT_SAMPLING  = float(os.getenv("RATE_EVENT_SAMPLING", "1.0"))

# Cache simples de políticas (60s)
_POLICY_CACHE: Dict[str, Any] = {"last": 0, "policies": []}
_CACHE_TTL_SEC = 60

def _load_policies():
    global _POLICY_CACHE
    now = time.time()
    if now - _POLICY_CACHE["last"] < _CACHE_TTL_SEC and _POLICY_CACHE["policies"]:
        return _POLICY_CACHE["policies"]
    with PolicySessionLocal() as db:
        policies = db.execute(
            select(RateLimitPolicy).where(RateLimitPolicy.enabled == True).order_by(desc(RateLimitPolicy.priority))
        ).scalars().all()
    _POLICY_CACHE = {"last": now, "policies": policies}
    return policies

def _match_policy(username: str, role: str, endpoint: str) -> Optional[RateLimitPolicy]:
    """
    Ordem de precedência pela priority (maior primeiro) + combinação.
    Recomende usar prioridades coerentes: user_endpoint > user > role_endpoint > role > endpoint > global.
    """
    policies = _load_policies()
    for p in policies:
        if p.level == "user_endpoint" and p.username == username and p.endpoint == endpoint:
            return p
        if p.level == "user" and p.username == username:
            return p
        if p.level == "role_endpoint" and p.role == role and p.endpoint == endpoint:
            return p
        if p.level == "role" and p.role == role:
            return p
        if p.level == "endpoint" and p.endpoint == endpoint:
            return p
        if p.level == "global":
            return p
    return None

def _get_effective_policy(username: str, role: str, endpoint: str) -> dict:
    p = _match_policy(username, role, endpoint)
    if p:
        return {
            "enabled": True,
            "window_sec": p.window_sec,
            "max_calls": p.max_calls,
            "block_sec": p.block_sec,
            "source": f"policy:{p.level}:{p.id}"
        }
    return {
        "enabled": FALLBACK_ENABLED,
        "window_sec": FALLBACK_WINDOW,
        "max_calls": FALLBACK_MAX,
        "block_sec": FALLBACK_BLOCK,
        "source": "fallback_env"
    }

def _is_blocked_db(username: str, endpoint: str) -> Optional[int]:
    """Verifica bloqueio manual ativo no BISOBEL. Retorna TTL (s) se bloqueado, senão None."""
    with PolicySessionLocal() as db:
        now = datetime.utcnow()
        blk = db.execute(
            select(RateLimitBlock).where(
                and_(
                    RateLimitBlock.username == username,
                    RateLimitBlock.endpoint == endpoint,
                    RateLimitBlock.cleared_at.is_(None),
                    RateLimitBlock.block_until > now
                )
            )
        ).scalars().first()
        if blk:
            ttl = int((blk.block_until - now).total_seconds())
            return max(ttl, 1)
    return None

def _log_event(username: str, role: str, endpoint: str, decision: str, rule_source: str, policy: dict, calls: Optional[int], reason: Optional[str]):
    if EVENT_SAMPLING < 1.0 and random.random() > EVENT_SAMPLING:
        return
    with PolicySessionLocal() as db:
        ev = RateLimitEvent(
            username=username,
            role=role,
            endpoint=endpoint,
            decision=decision,
            rule_source=rule_source,
            window_sec=policy.get("window_sec"),
            max_calls=policy.get("max_calls"),
            block_sec=policy.get("block_sec"),
            calls=calls,
            reason=reason
        )
        db.add(ev)
        db.commit()

def check_rate_limit(username: str, role: str, endpoint: str):
    """
    1) Verifica bloqueio manual no SQL (BISOBEL)
    2) Aplica política (SQL ou fallback) usando contadores no Redis (fixed window)
    3) Loga decisão em BISOBEL (amostrado)
    """
    # Bloqueio manual (DB)
    ttl_db = _is_blocked_db(username, endpoint)
    if ttl_db:
        _log_event(username, role, endpoint, "block", "manual_block", {}, None, f"DB block {ttl_db}s")
        raise PermissionError(f"Usuário bloqueado (DB). Aguarde {ttl_db}s")

    policy = _get_effective_policy(username, role, endpoint)
    if not policy["enabled"]:
        _log_event(username, role, endpoint, "allow", policy["source"], policy, None, "disabled")
        return

    window = policy["window_sec"]
    max_calls = policy["max_calls"]
    block_sec = policy["block_sec"]

    now_epoch = int(time.time())
    window_id = now_epoch // window
    key = f"rl:{username}:{endpoint}:{window_id}"
    block_key = f"rl:block:{username}:{endpoint}"

    # Bloqueio ativo em Redis?
    ttl_block = redis_client.ttl(block_key)
    if ttl_block and ttl_block > 0:
        _log_event(username, role, endpoint, "block", "redis_block", policy, None, f"TTL {ttl_block}s")
        raise PermissionError(f"Usuário bloqueado. Aguarde {ttl_block}s")

    # Incremento atômico + TTL
    pipe = redis_client.pipeline()
    pipe.incr(key)
    pipe.expire(key, window + block_sec)
    calls, _ = pipe.execute()

    if calls > max_calls:
        redis_client.setex(block_key, block_sec, "1")
        _log_event(username, role, endpoint, "block", "redis_counter", policy, int(calls), "exceeded")
        raise PermissionError(f"Limite excedido ({max_calls}/{window}s). Bloqueado por {block_sec}s")

    _log_event(username, role, endpoint, "allow", "redis_counter", policy, int(calls), None)
