# Chapter 15a — SQL: The Language Under the ORM

> EF Core generates SQL. Understanding that SQL means you can read the
> query log, spot the N+1, fix the missing index, and write the two
> complex queries that no ORM will ever produce cleanly. This chapter
> teaches the SQL you will actually use in a .NET project.

---

## 15a.1 What SQL Is and How .NET Talks to It

SQL is a declarative language — you describe *what* you want, not *how*
to retrieve it. The database engine figures out the execution plan.
Every relational database (SQLite, PostgreSQL, SQL Server, MySQL) speaks
a slightly different dialect but the core 95% is identical.

**How .NET connects:**

```
Your code
  └── EF Core / Dapper
        └── ADO.NET (SqlConnection / NpgsqlConnection / SqliteConnection)
              └── Database driver (TCP socket or file handle)
                    └── Database engine
```

EF Core is a layer on top of ADO.NET. When you want to bypass it, you
drop straight to ADO.NET or Dapper (§15.10).

---

## 15a.2 Installing a Database

### SQLite — zero install, file-based, perfect for dev and small apps

```bash
# No install needed. SQLite is bundled in the NuGet package.
dotnet add package Microsoft.Data.Sqlite

# Or with EF Core:
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
```

Create a database file and open it in the CLI:

```bash
# Install the sqlite3 CLI
# Linux:  sudo apt install sqlite3
# macOS:  brew install sqlite3
# NixOS:  nix-shell -p sqlite
# Windows: winget install SQLite.SQLite

sqlite3 myapp.db    # opens (or creates) myapp.db
.help               # show all dot-commands
.quit               # exit
```

### PostgreSQL — the right choice for production on Linux/macOS

```bash
# Linux (Debian/Ubuntu)
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo -u postgres psql              # connect as superuser

# macOS
brew install postgresql@16
brew services start postgresql@16
psql postgres

# NixOS — flake.nix devShell
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;
  initialScript = pkgs.writeText "init.sql" ''
    CREATE USER myapp WITH PASSWORD 'secret';
    CREATE DATABASE myapp OWNER myapp;
  '';
};

# Docker (fastest for dev — no local install)
docker run -d \
  --name pg-dev \
  -e POSTGRES_USER=myapp \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=myapp \
  -p 5432:5432 \
  postgres:16

# Connect
psql -h localhost -U myapp -d myapp
```

```bash
# NuGet
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
```

### SQL Server — Windows and enterprise .NET projects

```bash
# Docker (works on Linux/macOS too)
docker run -d \
  --name sqlserver-dev \
  -e "ACCEPT_EULA=Y" \
  -e "SA_PASSWORD=Your$tr0ngP@ss" \
  -p 1433:1433 \
  mcr.microsoft.com/mssql/server:2022-latest

# NuGet
dotnet add package Microsoft.EntityFrameworkCore.SqlServer
```

### Connection strings

```
SQLite:     Data Source=myapp.db
            Data Source=/home/user/.syncmesh/syncmesh.db

PostgreSQL: Host=localhost;Database=myapp;Username=myapp;Password=secret
            Host=localhost;Port=5432;Database=myapp;Username=myapp;Password=secret;SslMode=Require

SQL Server: Server=localhost,1433;Database=myapp;User Id=sa;Password=...;TrustServerCertificate=true
```

---

## 15a.3 Creating a Schema

A **schema** is the structure of your database: tables, columns, types,
constraints, and indexes. You define it in DDL (Data Definition Language).

### The core DDL commands

```sql
-- CREATE TABLE: define a table
CREATE TABLE users (
    id         INTEGER PRIMARY KEY,     -- SQLite auto-increments this
    email      TEXT    NOT NULL UNIQUE,
    name       TEXT    NOT NULL,
    created_at TEXT    NOT NULL DEFAULT (datetime('now', 'utc')),
    is_active  INTEGER NOT NULL DEFAULT 1
);

-- PostgreSQL equivalent (types differ slightly)
CREATE TABLE users (
    id         SERIAL PRIMARY KEY,         -- auto-incrementing integer
    -- or: id UUID PRIMARY KEY DEFAULT gen_random_uuid()
    email      TEXT        NOT NULL UNIQUE,
    name       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active  BOOLEAN     NOT NULL DEFAULT TRUE
);

-- SQL Server
CREATE TABLE users (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    email      NVARCHAR(320) NOT NULL,
    created_at DATETIMEOFFSET NOT NULL DEFAULT SYSUTCDATETIME(),
    is_active  BIT NOT NULL DEFAULT 1,
    CONSTRAINT UQ_users_email UNIQUE (email)
);

-- DROP TABLE: delete it entirely
DROP TABLE users;
DROP TABLE IF EXISTS users;     -- safe: no error if it doesn't exist

-- ALTER TABLE: change structure
ALTER TABLE users ADD COLUMN phone TEXT;
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users RENAME COLUMN name TO full_name;
```

### Column types — practical reference

| Concept | SQLite | PostgreSQL | SQL Server |
|---|---|---|---|
| Integer | `INTEGER` | `INTEGER` / `BIGINT` | `INT` / `BIGINT` |
| Auto ID | `INTEGER PRIMARY KEY` | `SERIAL` / `BIGSERIAL` | `INT IDENTITY(1,1)` |
| UUID | `TEXT` | `UUID` | `UNIQUEIDENTIFIER` |
| Short text | `TEXT` | `VARCHAR(n)` / `TEXT` | `NVARCHAR(n)` |
| Long text | `TEXT` | `TEXT` | `NVARCHAR(MAX)` |
| Decimal | `REAL` / `NUMERIC` | `NUMERIC(p,s)` | `DECIMAL(p,s)` |
| Boolean | `INTEGER` (0/1) | `BOOLEAN` | `BIT` |
| Date+Time | `TEXT` (ISO 8601) | `TIMESTAMPTZ` | `DATETIMEOFFSET` |
| Binary | `BLOB` | `BYTEA` | `VARBINARY(MAX)` |
| JSON | `TEXT` | `JSONB` | `NVARCHAR(MAX)` |

### Primary keys

```sql
-- Single column (most common)
id INTEGER PRIMARY KEY          -- SQLite
id SERIAL PRIMARY KEY           -- PostgreSQL

-- UUID primary key (portable, no auto-increment coordination needed)
id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16))))  -- SQLite hack
id UUID PRIMARY KEY DEFAULT gen_random_uuid()              -- PostgreSQL 13+

-- Composite primary key (two or more columns form the key)
CREATE TABLE folder_nodes (
    folder_id TEXT NOT NULL,
    node_id   TEXT NOT NULL,
    PRIMARY KEY (folder_id, node_id)
);
```

### Foreign keys and relationships

```sql
CREATE TABLE posts (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL,
    title      TEXT    NOT NULL,
    body       TEXT    NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_posts_users
        FOREIGN KEY (user_id)
        REFERENCES users (id)
        ON DELETE CASCADE    -- deleting a user deletes their posts
        -- ON DELETE SET NULL  -- sets user_id to NULL (user_id must be nullable)
        -- ON DELETE RESTRICT   -- prevents deletion if posts exist (default)
);

-- SQLite: foreign keys are OFF by default. Turn them on per-connection:
PRAGMA foreign_keys = ON;
```

### Constraints

```sql
CREATE TABLE products (
    id        SERIAL PRIMARY KEY,
    sku       TEXT    NOT NULL,
    name      TEXT    NOT NULL,
    price     NUMERIC(10,2) NOT NULL,
    stock     INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT uq_products_sku UNIQUE (sku),
    CONSTRAINT chk_price_positive CHECK (price >= 0),
    CONSTRAINT chk_stock_nonneg   CHECK (stock  >= 0)
);
```

### Indexes

```sql
-- Single column index (speeds up WHERE, ORDER BY on that column)
CREATE INDEX idx_posts_user_id ON posts (user_id);

-- Unique index (enforces uniqueness, also speeds up lookups)
CREATE UNIQUE INDEX idx_users_email ON users (email);

-- Composite index (useful for queries that filter on both columns)
CREATE INDEX idx_file_snapshots_folder_path
    ON file_snapshots (folder_id, path);

-- Partial index (PostgreSQL) — only index rows matching a condition
CREATE INDEX idx_active_users ON users (email)
    WHERE is_active = TRUE;

-- Drop an index
DROP INDEX IF EXISTS idx_posts_user_id;

-- See which indexes exist
-- SQLite:
SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'index';
-- PostgreSQL:
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'posts';
```

**When to add an index:**
- Any column used in `WHERE`, `JOIN ON`, or `ORDER BY` in a frequent query
- Foreign key columns (databases don't automatically index them)
- Any column used in `GROUP BY` or aggregated frequently

**When NOT to add an index:**
- Small tables (< 10,000 rows) — full scan is faster
- Columns with very low cardinality (boolean, small enum) — rarely helps
- Tables with heavy writes and infrequent reads — indexes slow writes

---

## 15a.4 The SELECT Statement — Complete Reference

```sql
-- Full structure (every clause is optional except SELECT ... FROM)
SELECT   [DISTINCT] column_list
FROM     table_name [alias]
[JOIN    other_table ON condition]
[WHERE   condition]
[GROUP BY columns]
[HAVING  aggregate_condition]
[ORDER BY column [ASC|DESC]]
[LIMIT   n]
[OFFSET  m];
```

### Basic queries

```sql
-- All columns
SELECT * FROM users;

-- Specific columns
SELECT id, email, name FROM users;

-- Column alias
SELECT id, email AS user_email, name AS full_name FROM users;

-- Computed column
SELECT id, name, price * 1.2 AS price_with_tax FROM products;

-- DISTINCT: remove duplicate rows
SELECT DISTINCT country FROM users;

-- Filter with WHERE
SELECT * FROM users WHERE is_active = TRUE;
SELECT * FROM posts  WHERE user_id = 42;
SELECT * FROM users  WHERE name LIKE 'Alice%';   -- starts with Alice
SELECT * FROM users  WHERE name LIKE '%son';      -- ends with son
SELECT * FROM users  WHERE email ILIKE '%gmail%'; -- PostgreSQL: case-insensitive

-- Multiple conditions
SELECT * FROM posts WHERE user_id = 42 AND created_at > '2024-01-01';
SELECT * FROM users WHERE country = 'DE' OR country = 'AT';
SELECT * FROM users WHERE country IN ('DE', 'AT', 'CH');
SELECT * FROM users WHERE country NOT IN ('US', 'CA');

-- NULL handling
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
-- Never use = NULL — it always returns nothing
```

### Sorting and limiting

```sql
-- Sort ascending (default)
SELECT * FROM users ORDER BY name;
SELECT * FROM users ORDER BY name ASC;

-- Sort descending
SELECT * FROM posts ORDER BY created_at DESC;

-- Sort by multiple columns
SELECT * FROM posts ORDER BY user_id ASC, created_at DESC;

-- Limit results (pagination)
SELECT * FROM posts ORDER BY created_at DESC LIMIT 10;
SELECT * FROM posts ORDER BY created_at DESC LIMIT 10 OFFSET 20;  -- page 3

-- PostgreSQL: window-function based pagination is more efficient for deep pages
```

### Aggregates

```sql
COUNT(*),  COUNT(column)  -- count rows (COUNT(*) includes NULLs, COUNT(col) excludes)
SUM(column)               -- total
AVG(column)               -- mean
MIN(column), MAX(column)  -- extremes

-- Examples
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM users WHERE is_active = TRUE;
SELECT AVG(price) FROM products;
SELECT SUM(price * quantity) AS total FROM order_lines WHERE order_id = 5;
SELECT MIN(created_at), MAX(created_at) FROM posts;

-- GROUP BY: aggregate per group
SELECT user_id, COUNT(*) AS post_count
FROM posts
GROUP BY user_id
ORDER BY post_count DESC;

-- HAVING: filter on aggregated results (WHERE runs before aggregation, HAVING after)
SELECT user_id, COUNT(*) AS post_count
FROM posts
GROUP BY user_id
HAVING COUNT(*) > 10;    -- only users with more than 10 posts
```

---

## 15a.5 JOINs

A JOIN combines rows from two tables based on a condition.

```
users               posts
id  name            id  user_id  title
1   Alice           1   1        "Hello"
2   Bob             2   1        "World"
3   Carol           3   2        "Foo"
                                 (no post for Carol)
```

```sql
-- INNER JOIN: only rows that match in BOTH tables
SELECT u.name, p.title
FROM   users u
INNER JOIN posts p ON p.user_id = u.id;

-- Result: Alice/Hello, Alice/World, Bob/Foo  (Carol excluded — no posts)

-- LEFT JOIN (LEFT OUTER JOIN): all rows from left table, NULLs for non-matching right
SELECT u.name, p.title
FROM   users u
LEFT JOIN posts p ON p.user_id = u.id;

-- Result: Alice/Hello, Alice/World, Bob/Foo, Carol/NULL

-- RIGHT JOIN: all rows from right table (less common — just flip the tables and LEFT JOIN)

-- FULL OUTER JOIN: all rows from both, NULLs where no match (PostgreSQL/SQL Server)
SELECT u.name, p.title
FROM   users u
FULL OUTER JOIN posts p ON p.user_id = u.id;

-- Self-join: join a table to itself (e.g. manager-employee hierarchy)
SELECT e.name AS employee, m.name AS manager
FROM   employees e
LEFT JOIN employees m ON m.id = e.manager_id;

-- Multi-table join
SELECT u.name, p.title, c.body AS comment
FROM   users u
JOIN   posts    p ON p.user_id    = u.id
JOIN   comments c ON c.post_id    = p.id
WHERE  u.id = 42
ORDER  BY p.created_at DESC, c.created_at ASC;
```

---

## 15a.6 DML — Inserting, Updating, Deleting

DML (Data Manipulation Language) is how you change data.

```sql
-- INSERT: add rows
INSERT INTO users (email, name) VALUES ('alice@example.com', 'Alice');

-- Multiple rows in one statement
INSERT INTO users (email, name) VALUES
    ('bob@example.com',   'Bob'),
    ('carol@example.com', 'Carol');

-- INSERT ... RETURNING (PostgreSQL): get the generated ID back
INSERT INTO users (email, name)
VALUES ('dave@example.com', 'Dave')
RETURNING id;

-- INSERT OR IGNORE (SQLite): skip if UNIQUE constraint would fire
INSERT OR IGNORE INTO users (email, name) VALUES ('alice@example.com', 'Alice');

-- UPSERT (INSERT ... ON CONFLICT) — PostgreSQL and SQLite 3.24+
INSERT INTO users (email, name)
VALUES ('alice@example.com', 'Alice Updated')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- UPDATE: modify existing rows
UPDATE users SET name = 'Alicia' WHERE id = 1;
UPDATE users SET name = 'Alicia', is_active = FALSE WHERE email = 'alice@example.com';

-- UPDATE with subquery
UPDATE posts
SET title = title || ' [edited]'
WHERE user_id IN (SELECT id FROM users WHERE is_active = FALSE);

-- DELETE: remove rows
DELETE FROM users WHERE id = 1;
DELETE FROM users WHERE is_active = FALSE;
DELETE FROM posts WHERE created_at < '2020-01-01';

-- TRUNCATE: fast delete of all rows (PostgreSQL / SQL Server — not SQLite)
TRUNCATE TABLE audit_logs;
TRUNCATE TABLE audit_logs RESTART IDENTITY;   -- also resets sequences
```

---

## 15a.7 Subqueries and CTEs

```sql
-- Subquery in WHERE
SELECT * FROM posts
WHERE user_id IN (
    SELECT id FROM users WHERE country = 'DE'
);

-- Subquery in FROM (derived table)
SELECT u.name, stats.post_count
FROM users u
JOIN (
    SELECT user_id, COUNT(*) AS post_count
    FROM posts
    GROUP BY user_id
) AS stats ON stats.user_id = u.id;

-- CTE (Common Table Expression) — WITH clause
-- Cleaner than nested subqueries. Use for readability.
WITH active_users AS (
    SELECT id, name FROM users WHERE is_active = TRUE
),
user_post_counts AS (
    SELECT user_id, COUNT(*) AS cnt
    FROM posts
    GROUP BY user_id
)
SELECT au.name, COALESCE(upc.cnt, 0) AS posts
FROM   active_users au
LEFT JOIN user_post_counts upc ON upc.user_id = au.id
ORDER  BY posts DESC;

-- Recursive CTE: traverse hierarchical data (org chart, folder tree)
WITH RECURSIVE folder_tree AS (
    -- Base case: root folder
    SELECT id, parent_id, name, 0 AS depth
    FROM   folders
    WHERE  parent_id IS NULL

    UNION ALL

    -- Recursive case: children
    SELECT f.id, f.parent_id, f.name, ft.depth + 1
    FROM   folders f
    JOIN   folder_tree ft ON ft.id = f.parent_id
)
SELECT depth, name FROM folder_tree ORDER BY depth, name;
```

---

## 15a.8 Window Functions

Window functions compute a value over a "window" of rows relative to the
current row — without collapsing rows like GROUP BY does.

```sql
-- Syntax
function_name() OVER (
    [PARTITION BY columns]   -- divide into groups (like GROUP BY but rows kept)
    [ORDER BY columns]       -- define order within the window
    [ROWS BETWEEN ...]       -- frame specification
)

-- ROW_NUMBER: unique sequential number per partition
SELECT
    id,
    user_id,
    title,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rn
FROM posts;
-- rn=1 is the most recent post per user

-- Get the latest post per user (a very common pattern)
SELECT id, user_id, title, created_at
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rn
    FROM posts
) ranked
WHERE rn = 1;

-- RANK / DENSE_RANK: like ROW_NUMBER but handles ties
-- RANK: 1, 2, 2, 4 (gap after tie)
-- DENSE_RANK: 1, 2, 2, 3 (no gap)

-- LAG / LEAD: access previous / next row's value
SELECT
    date,
    revenue,
    LAG(revenue, 1) OVER (ORDER BY date) AS prev_revenue,
    revenue - LAG(revenue, 1) OVER (ORDER BY date) AS change
FROM daily_revenue;

-- Running total (cumulative sum)
SELECT
    date,
    revenue,
    SUM(revenue) OVER (ORDER BY date) AS cumulative_revenue
FROM daily_revenue;

-- Moving average (last 7 days)
SELECT
    date,
    revenue,
    AVG(revenue) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7d
FROM daily_revenue;
```

---

## 15a.9 Transactions

A transaction groups SQL statements so they either all succeed or all fail.

```sql
BEGIN;                          -- or BEGIN TRANSACTION

INSERT INTO accounts (id, balance) VALUES (1, 1000);
INSERT INTO accounts (id, balance) VALUES (2, 500);

UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;

COMMIT;    -- make changes permanent
-- or:
ROLLBACK;  -- undo everything since BEGIN

-- Savepoints (nested rollback)
BEGIN;
    INSERT INTO orders (id) VALUES (99);
    SAVEPOINT before_items;
        INSERT INTO order_items VALUES (99, 'bad-product', 1);
    ROLLBACK TO SAVEPOINT before_items;  -- undo only the bad insert
    INSERT INTO order_items VALUES (99, 'good-product', 1);
COMMIT;
```

**Isolation levels** (PostgreSQL):

| Level | Dirty Read | Non-Repeatable | Phantom |
|---|---|---|---|
| READ UNCOMMITTED | possible | possible | possible |
| READ COMMITTED (default) | prevented | possible | possible |
| REPEATABLE READ | prevented | prevented | possible |
| SERIALIZABLE | prevented | prevented | prevented |

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN;
...
COMMIT;
```

---

## 15a.10 Practical Schema: The Complete Sync.Mesh Example

This is the full schema for the Sync.Mesh project — written as raw SQL
before letting EF Core generate it from C# models.

```sql
-- ── Enable foreign keys (SQLite only — must run per-connection) ────────────
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;   -- better concurrent read performance

-- ── nodes ─────────────────────────────────────────────────────────────────
CREATE TABLE nodes (
    id                    TEXT    NOT NULL PRIMARY KEY,  -- NodeId (GUID as text)
    name                  TEXT    NOT NULL,
    endpoint              TEXT    NOT NULL,              -- "host:port"
    cert_fingerprint      TEXT    NOT NULL,
    platform              TEXT    NOT NULL,              -- "Linux"|"Windows"|...
    paired_at             TEXT    NOT NULL,              -- ISO 8601 UTC
    last_seen_at          TEXT,
    is_active             INTEGER NOT NULL DEFAULT 1,
    is_local              INTEGER NOT NULL DEFAULT 0,    -- exactly one row = TRUE
    prefer_offload_compute INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_nodes_is_local ON nodes (is_local)
    WHERE is_local = 1;

-- ── sync_folders ──────────────────────────────────────────────────────────
CREATE TABLE sync_folders (
    id                      TEXT    NOT NULL PRIMARY KEY,
    local_path              TEXT    NOT NULL UNIQUE,
    label                   TEXT    NOT NULL,
    is_enabled              INTEGER NOT NULL DEFAULT 1,
    default_conflict_policy TEXT    NOT NULL DEFAULT 'LastWriteWins',
    created_at              TEXT    NOT NULL
);

-- ── sync_folder_nodes (many-to-many) ──────────────────────────────────────
CREATE TABLE sync_folder_nodes (
    folder_id TEXT NOT NULL REFERENCES sync_folders (id) ON DELETE CASCADE,
    node_id   TEXT NOT NULL REFERENCES nodes (id)         ON DELETE CASCADE,
    PRIMARY KEY (folder_id, node_id)
);

-- ── file_snapshots ────────────────────────────────────────────────────────
CREATE TABLE file_snapshots (
    id          TEXT    NOT NULL PRIMARY KEY,
    folder_id   TEXT    NOT NULL REFERENCES sync_folders (id) ON DELETE CASCADE,
    path        TEXT    NOT NULL,
    hash        TEXT    NOT NULL,   -- Blake3, 64 hex chars; empty = deleted
    size        INTEGER NOT NULL,
    modified_at TEXT    NOT NULL,
    owner_node  TEXT    NOT NULL REFERENCES nodes (id),
    is_deleted  INTEGER NOT NULL DEFAULT 0,
    updated_at  TEXT    NOT NULL
);

CREATE UNIQUE INDEX idx_snapshots_folder_path_node
    ON file_snapshots (folder_id, path, owner_node);
CREATE INDEX idx_snapshots_folder_node
    ON file_snapshots (folder_id, owner_node);

-- ── sync_conflicts ────────────────────────────────────────────────────────
CREATE TABLE sync_conflicts (
    id              TEXT PRIMARY KEY,
    folder_id       TEXT NOT NULL REFERENCES sync_folders (id) ON DELETE CASCADE,
    path            TEXT NOT NULL,
    local_node      TEXT NOT NULL REFERENCES nodes (id),
    remote_node     TEXT NOT NULL REFERENCES nodes (id),
    local_modified  TEXT NOT NULL,
    remote_modified TEXT NOT NULL,
    detected_at     TEXT NOT NULL,
    resolved_at     TEXT,
    resolution      TEXT   -- 'accept_local'|'accept_remote'|'keep_both'
);

CREATE INDEX idx_conflicts_unresolved ON sync_conflicts (folder_id)
    WHERE resolved_at IS NULL;

-- ── sync_events (audit log) ───────────────────────────────────────────────
CREATE TABLE sync_events (
    id          TEXT    PRIMARY KEY,
    type        TEXT    NOT NULL,   -- 'push'|'pull'|'conflict'|'error'|'connect'
    peer_node   TEXT    REFERENCES nodes (id),
    folder_id   TEXT    REFERENCES sync_folders (id),
    path        TEXT,
    bytes_moved INTEGER,
    duration_ms INTEGER,
    error       TEXT,
    occurred_at TEXT    NOT NULL
);

CREATE INDEX idx_events_occurred_at ON sync_events (occurred_at DESC);
CREATE INDEX idx_events_folder      ON sync_events (folder_id, occurred_at DESC);

-- ── app_settings (key-value) ──────────────────────────────────────────────
CREATE TABLE app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- ── licences ──────────────────────────────────────────────────────────────
CREATE TABLE licences (
    key             TEXT PRIMARY KEY,
    email           TEXT    NOT NULL,
    includes_git_sync INTEGER NOT NULL DEFAULT 0,
    issued_at       TEXT    NOT NULL,
    expires_at      TEXT    NOT NULL,
    is_active       INTEGER NOT NULL DEFAULT 1
);
```

---

## 15a.11 Common SQL Patterns You Will Write Every Week

```sql
-- ── Upsert: insert or update on conflict ──────────────────────────────────
INSERT INTO file_snapshots (id, folder_id, path, hash, size, modified_at, owner_node, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now', 'utc'))
ON CONFLICT (folder_id, path, owner_node)
DO UPDATE SET
    hash        = EXCLUDED.hash,
    size        = EXCLUDED.size,
    modified_at = EXCLUDED.modified_at,
    is_deleted  = EXCLUDED.is_deleted,
    updated_at  = datetime('now', 'utc');

-- ── Soft delete ───────────────────────────────────────────────────────────
-- Instead of DELETE, mark a row as deleted
UPDATE file_snapshots
SET    is_deleted = 1, updated_at = datetime('now', 'utc')
WHERE  folder_id = ? AND path = ? AND owner_node = ?;

-- ── Pagination (keyset / cursor — faster than OFFSET for deep pages) ──────
-- "Give me the next 20 events after id X"
SELECT * FROM sync_events
WHERE  occurred_at < ?   -- cursor value from last row of previous page
ORDER  BY occurred_at DESC
LIMIT  20;

-- ── Top N per group (latest snapshot per file per folder) ─────────────────
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY folder_id, path ORDER BY modified_at DESC) AS rn
    FROM file_snapshots
    WHERE is_deleted = 0
) ranked
WHERE rn = 1;

-- ── Counts with conditional aggregation ───────────────────────────────────
SELECT
    folder_id,
    COUNT(*)                                    AS total_files,
    COUNT(*) FILTER (WHERE is_deleted = 0)      AS active_files,    -- PostgreSQL
    SUM(CASE WHEN is_deleted = 0 THEN 1 END)    AS active_files_sq, -- SQLite/any
    SUM(size) FILTER (WHERE is_deleted = 0)     AS total_bytes
FROM file_snapshots
GROUP BY folder_id;

-- ── Existence check (faster than COUNT) ───────────────────────────────────
-- In application code, use: SELECT EXISTS(...)
SELECT EXISTS (
    SELECT 1 FROM sync_conflicts
    WHERE folder_id = ? AND resolved_at IS NULL
) AS has_conflicts;
```

---

## 15a.12 Using SQL Directly in .NET (Without EF Core)

### ADO.NET — the raw layer

```csharp
using Microsoft.Data.Sqlite;

await using var connection = new SqliteConnection("Data Source=myapp.db");
await connection.OpenAsync(ct);

// Parameterised query — always use parameters, never string-concatenate
await using var cmd = connection.CreateCommand();
cmd.CommandText = """
    SELECT id, email, name FROM users
    WHERE is_active = @active AND country = @country
    ORDER BY name
    LIMIT @limit
    """;
cmd.Parameters.AddWithValue("@active",  1);
cmd.Parameters.AddWithValue("@country", "DE");
cmd.Parameters.AddWithValue("@limit",   50);

await using var reader = await cmd.ExecuteReaderAsync(ct);
while (await reader.ReadAsync(ct))
{
    var id    = reader.GetInt64(reader.GetOrdinal("id"));
    var email = reader.GetString(reader.GetOrdinal("email"));
    var name  = reader.GetString(reader.GetOrdinal("name"));
    Console.WriteLine($"{id}: {name} <{email}>");
}
```

### Dapper — thin mapping layer, raw SQL

```csharp
// dotnet add package Dapper
using Dapper;
using Microsoft.Data.Sqlite;

await using var db = new SqliteConnection("Data Source=myapp.db");

// Query → list of typed objects
var users = await db.QueryAsync<User>(
    "SELECT * FROM users WHERE is_active = @Active ORDER BY name",
    new { Active = 1 });

// Single row
var user = await db.QuerySingleOrDefaultAsync<User>(
    "SELECT * FROM users WHERE id = @Id", new { Id = 42 });

// Execute (INSERT/UPDATE/DELETE) — returns affected rows
var rows = await db.ExecuteAsync(
    "UPDATE users SET name = @Name WHERE id = @Id",
    new { Name = "Alice", Id = 1 });

// Multi-result: execute multiple SQL statements
using var multi = await db.QueryMultipleAsync("""
    SELECT * FROM users WHERE id = @Id;
    SELECT * FROM posts WHERE user_id = @Id ORDER BY created_at DESC LIMIT 5;
    """, new { Id = 42 });

var user2  = await multi.ReadSingleAsync<User>();
var posts  = await multi.ReadAsync<Post>();
```

---

## 15a.13 Reading the EF Core SQL Log

When you use EF Core, it generates SQL. Reading that SQL is non-negotiable
for production apps.

```csharp
// appsettings.Development.json
{
  "Logging": {
    "LogLevel": {
      "Microsoft.EntityFrameworkCore.Database.Command": "Information"
    }
  }
}
```

This logs every query EF Core sends. A query that looks like this in C#:

```csharp
var posts = await db.Posts
    .Where(p => p.UserId == userId)
    .Include(p => p.Comments)
    .ToListAsync(ct);
```

Generates this SQL (simplified):

```sql
-- First query: load posts
SELECT p.id, p.title, p.user_id, p.created_at
FROM   posts p
WHERE  p.user_id = @userId;

-- Second query: load ALL comments for those post IDs (SELECT N+1 if in a loop!)
SELECT c.id, c.post_id, c.body
FROM   comments c
WHERE  c.post_id IN (1, 2, 3, ...);
```

The N+1 problem is when EF Core issues one query to get N entities then
N additional queries (one per entity). It is the most common performance
mistake with ORMs. The fix is to use `Include` at the source or write a
join manually with `QueryAsync` via Dapper.

---

## 15a.14 Useful SQLite Pragmas

```sql
-- Check and configure SQLite
PRAGMA journal_mode;             -- see current mode
PRAGMA journal_mode = WAL;       -- WAL = Write-Ahead Logging; best for concurrent reads
PRAGMA foreign_keys = ON;        -- enforce FK constraints (off by default!)
PRAGMA cache_size = -64000;      -- 64 MB page cache
PRAGMA synchronous = NORMAL;     -- balance durability vs speed
PRAGMA temp_store = MEMORY;      -- use RAM for temp tables

-- Analyse and maintain
PRAGMA table_info(users);        -- show column names and types
PRAGMA index_list(users);        -- show indexes on a table
PRAGMA integrity_check;          -- verify database is not corrupted
VACUUM;                          -- reclaim space after many deletes
ANALYZE;                         -- update query planner statistics

-- Explain a query plan (use to verify an index is being used)
EXPLAIN QUERY PLAN
SELECT * FROM file_snapshots
WHERE folder_id = 'abc' AND path = 'readme.md';
-- Output will say "USING INDEX idx_snapshots_folder_path_node" if the index fires
```

---

## Summary

| Topic | Key point |
|---|---|
| Install | SQLite = no install; PostgreSQL = `brew`/`apt`/Docker; SQL Server = Docker |
| Schema | `CREATE TABLE`, `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `CHECK`, `INDEX` |
| Query | `SELECT … FROM … WHERE … JOIN … GROUP BY … ORDER BY … LIMIT` |
| Mutate | `INSERT`, `UPDATE`, `DELETE`, `UPSERT ON CONFLICT` |
| Structure | CTEs (`WITH`) for readability; window functions for ranking/running totals |
| Transactions | `BEGIN` / `COMMIT` / `ROLLBACK` — always wrap multi-step mutations |
| .NET | ADO.NET for raw control; Dapper for thin mapping; EF Core for full ORM |
| Performance | Read the generated SQL log; check `EXPLAIN QUERY PLAN`; index FK columns |

See **Ch 15 §15.10** for Dapper integration and **Ch 15 §15.12** for the
critical `IEnumerable` vs `IQueryable` distinction.
