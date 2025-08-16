-- Banco: BISOBEL
-- Execute em BISOBEL (ou ajuste schema conforme necessário)

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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'rate_limit_policy')
BEGIN
  CREATE TABLE dbo.rate_limit_policy (
    id INT IDENTITY PRIMARY KEY,
    level NVARCHAR(20) NOT NULL, -- 'global', 'role', 'user', 'endpoint', 'user_endpoint', 'role_endpoint'
    role NVARCHAR(50) NULL,
    username NVARCHAR(100) NULL,
    endpoint NVARCHAR(200) NULL,
    window_sec INT NOT NULL,
    max_calls INT NOT NULL,
    block_sec INT NOT NULL,
    enabled BIT NOT NULL DEFAULT 1,
    priority INT NOT NULL DEFAULT 0, -- maior ganha
    notes NVARCHAR(500) NULL,
    created_by NVARCHAR(100) NULL,
    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
  );

  CREATE INDEX IX_rate_limit_policy_lookup
  ON dbo.rate_limit_policy(level, username, role, endpoint, enabled, priority);
END;

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'rate_limit_block')
BEGIN
  CREATE TABLE dbo.rate_limit_block (
    id BIGINT IDENTITY PRIMARY KEY,
    username NVARCHAR(100) NOT NULL,
    endpoint NVARCHAR(200) NOT NULL,
    block_until DATETIME2 NOT NULL,
    reason NVARCHAR(200) NULL,
    created_by NVARCHAR(100) NULL,
    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    cleared_at DATETIME2 NULL,
    cleared_by NVARCHAR(100) NULL
  );
  CREATE INDEX IX_rate_limit_block_active
  ON dbo.rate_limit_block(username, endpoint) INCLUDE (block_until, cleared_at);
END;

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'rate_limit_event')
BEGIN
  CREATE TABLE dbo.rate_limit_event (
    id BIGINT IDENTITY PRIMARY KEY,
    ts DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    username NVARCHAR(100) NOT NULL,
    role NVARCHAR(50) NOT NULL,
    endpoint NVARCHAR(200) NOT NULL,
    decision NVARCHAR(20) NOT NULL, -- 'allow' | 'block'
    rule_source NVARCHAR(50) NOT NULL, -- 'redis_counter' | 'manual_block' | 'policy'
    window_sec INT NULL,
    max_calls INT NULL,
    block_sec INT NULL,
    calls INT NULL,
    reason NVARCHAR(200) NULL
  );
  CREATE INDEX IX_rate_limit_event_q
  ON dbo.rate_limit_event(ts, username, endpoint, decision);
END;

-- Usuário admin de exemplo (senha: Admin@123) - troque em produção!
IF NOT EXISTS (SELECT 1 FROM dbo.admin_user WHERE username = 'admin')
BEGIN
  INSERT INTO dbo.admin_user (username, password_hash, role)
  VALUES ('admin', '$2b$12$Iu4ee7tCD9Z0P3S9qf2J4e4aK7E0y4k5.5rB8T1w8kZQ0hGq1cFfK', 'admin');
  -- hash gerado por bcrypt para "Admin@123"
END;
