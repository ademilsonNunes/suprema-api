from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import String, Integer, Boolean, DateTime, Text
from datetime import datetime

class Base(DeclarativeBase):
    pass

class AdminUser(Base):
    __tablename__ = "admin_user"
    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(50), default="admin", nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), default=datetime.utcnow, nullable=False)

class RateLimitPolicy(Base):
    __tablename__ = "rate_limit_policy"
    id: Mapped[int] = mapped_column(primary_key=True)
    level: Mapped[str] = mapped_column(String(20), nullable=False)  # global, role, user, endpoint, user_endpoint, role_endpoint
    role: Mapped[str | None] = mapped_column(String(50))
    username: Mapped[str | None] = mapped_column(String(100))
    endpoint: Mapped[str | None] = mapped_column(String(200))
    window_sec: Mapped[int]
    max_calls: Mapped[int]
    block_sec: Mapped[int]
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    priority: Mapped[int] = mapped_column(Integer, default=0)
    notes: Mapped[str | None] = mapped_column(String(500))
    created_by: Mapped[str | None] = mapped_column(String(100))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), default=datetime.utcnow, nullable=False)

class RateLimitBlock(Base):
    __tablename__ = "rate_limit_block"
    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(100))
    endpoint: Mapped[str] = mapped_column(String(200))
    block_until: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    reason: Mapped[str | None] = mapped_column(String(200))
    created_by: Mapped[str | None] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), default=datetime.utcnow)
    cleared_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=False))
    cleared_by: Mapped[str | None] = mapped_column(String(100))

class RateLimitEvent(Base):
    __tablename__ = "rate_limit_event"
    id: Mapped[int] = mapped_column(primary_key=True)
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=False), default=datetime.utcnow)
    username: Mapped[str] = mapped_column(String(100))
    role: Mapped[str] = mapped_column(String(50))
    endpoint: Mapped[str] = mapped_column(String(200))
    decision: Mapped[str] = mapped_column(String(20))  # allow | block
    rule_source: Mapped[str] = mapped_column(String(50))
    window_sec: Mapped[int | None] = mapped_column(Integer)
    max_calls: Mapped[int | None] = mapped_column(Integer)
    block_sec: Mapped[int | None] = mapped_column(Integer)
    calls: Mapped[int | None] = mapped_column(Integer)
    reason: Mapped[str | None] = mapped_column(String(200))
