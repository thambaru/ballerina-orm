## Plan: Ballerina ORM Package (Prisma-like)

Build a Prisma-inspired ORM for Ballerina using annotated record types as the schema source of truth, with a type-safe query builder client, full relation support, migration tooling, and MySQL + PostgreSQL backends. Delivered as a Ballerina Central package + companion `bal orm` CLI tool.

### Architecture — Three Deliverables

1. **`thambaru/bal_orm.orm`** — Core library: annotations, query builder API, relation resolution, connection management. Wraps `ballerinax/mysql` and `ballerinax/postgresql`.
2. **`thambaru/bal_orm` compiler plugin** — Reads annotated records at compile time, generates typed CRUD methods, input/output types, and query builders per model.
3. **`bal orm` CLI tool** — Migration engine: schema introspection, diffing, SQL migration generation, apply/rollback.

---

### Phase 1 — Core Schema Definition (annotations + record types)

**Step 1.1: Annotation library** — Define annotations for DB mapping:
- `@orm:Entity` on record — table name, schema (pg), engine (mysql)
- `@orm:Id` / `@orm:AutoIncrement` on field — primary key
- `@orm:Column` on field — column name, type, length, nullable, unique, default
- `@orm:Index` on record — single/composite indexes
- `@orm:Relation` on field — type (ONE_TO_ONE, ONE_TO_MANY, MANY_TO_MANY), references, foreignKey, joinTable
- `@orm:CreatedAt` / `@orm:UpdatedAt` — auto-managed timestamps
- `@orm:Ignore` — exclude field from DB

Example schema:
```ballerina
@orm:Entity {tableName: "users"}
@orm:Index {columns: ["email"], unique: true}
public type User record {|
    @orm:Id @orm:AutoIncrement
    int id;
    @orm:Column {length: 255, nullable: false}
    string email;
    string name;
    @orm:CreatedAt
    time:Utc createdAt;
    @orm:Relation {type: ONE_TO_MANY}
    Post[] posts?;
|};
```

**Step 1.2: Schema IR** — Parse annotations into an intermediate representation (`ModelDefinition`, `ColumnDefinition`, `RelationDefinition`, `SchemaGraph`) for use by the query builder and migration engine.

**Files:** `modules/orm/annotations.bal`, `modules/orm/schema/model.bal`, `modules/orm/schema/parser.bal`, `modules/orm/schema/validator.bal`

---

### Phase 2 — Query Builder API (*depends on Phase 1*)

**Step 2.1: Fluent builder** — Prisma-style type-safe API:
```ballerina
User[] users = check orm:from(User)
    .where({email: {contains: "@example.com"}})
    .orderBy({createdAt: orm:DESC})
    .skip(10).take(20)
    .findMany();

User newUser = check orm:from(User).create({email: "a@b.com", name: "Alice"});
```
Methods: `findMany`, `findUnique`, `findFirst`, `create`, `createMany`, `update`, `updateMany`, `upsert`, `delete`, `deleteMany`, `count`, `aggregate`.

**Step 2.2: Filter operators** — `equals`, `not`, `in`, `notIn`, `lt/lte/gt/gte`, `contains`, `startsWith`, `endsWith`, `AND/OR/NOT`, `isNull`.

**Step 2.3: Relation queries** — `include` (eager loading via JOINs or batched queries), `select` (projection), nested writes (create parent + children atomically).

**Step 2.4: Raw SQL escape hatch** — `orm:rawQuery(...)` and `orm:rawExecute(...)` using Ballerina's parameterized query templates.

**Step 2.5: Dialect-aware SQL generation** — Query AST → SQL string with MySQL and PostgreSQL dialect modules.

**Files:** `modules/orm/query/builder.bal`, `filter.bal`, `select.bal`, `include.bal`, `sql_generator.bal`, `modules/orm/dialects/mysql.bal`, `postgresql.bal`

---

### Phase 3 — Database Client & Connection (*parallel with Phase 2*)

**Step 3.1: ORM Client** — Single entry point wrapping the database drivers:
```ballerina
orm:Client ormClient = check new ({
    provider: orm:MYSQL,
    host: "localhost", port: 3306,
    user: "root", password: "password", database: "myapp"
});
// or: orm:Client ormClient = check new ({url: "postgresql://..."});
```

**Step 3.2: Transaction support** — Use Ballerina's native `transaction {}` blocks; the ORM client participates automatically.

**Step 3.3: Connection pooling** — Delegate to underlying driver pool configs.

**Files:** `modules/orm/client.bal`, `modules/orm/types.bal`, `modules/orm/connection/pool.bal`, `connection/url_parser.bal`

---

### Phase 4 — Compiler Plugin (*depends on Phase 1 & 2*)

**Step 4.1: Plugin scaffold** — Ballerina compiler plugin that scans for `@orm:Entity` records.

**Step 4.2: Code generation** — For each entity, generate:
- `UserCreateInput`, `UserUpdateInput` — typed input records
- `UserWhereInput`, `UserOrderByInput` — typed filter/sort records
- `UserInclude` — relation eager-loading config
- Type-safe CRUD wrappers bound to the model

**Step 4.3: Compile-time validation** — Verify relation FK existence/type matching, column type compatibility, warn on missing FK indexes.

**Files:** `modules/orm-compiler-plugin/plugin.bal`, `analyzer.bal`, `generator.bal`, `type_mapper.bal`

---

### Phase 5 — Migration Engine / CLI (*depends on Phase 1*)

**Step 5.1: Schema introspection** — Read live DB schema via `INFORMATION_SCHEMA` (MySQL) / `pg_catalog` (PostgreSQL).

**Step 5.2: Schema diffing** — Compare desired state (annotated records) vs actual DB state → detect added/removed/renamed tables, columns, indexes, relations.

**Step 5.3: Migration file generation** — Timestamped directories with SQL files:
```
migrations/
├── 20260309120000_init/migration.sql
├── 20260310143000_add_posts/migration.sql
└── migration_lock.toml
```
Tracking via `_orm_migrations` table in the target DB.

**Step 5.4: CLI commands:**
| Command | Description |
|---|---|
| `bal orm init` | Initialize config + migrations dir |
| `bal orm migrate dev` | Generate + apply migration (dev) |
| `bal orm migrate deploy` | Apply pending migrations (prod) |
| `bal orm migrate reset` | Reset DB (dev only) |
| `bal orm migrate status` | Show applied/pending migrations |
| `bal orm db push` | Push schema directly, no migration file |
| `bal orm db pull` | Introspect DB → generate record types |
| `bal orm generate` | Trigger client code generation |

**Files:** `modules/orm-cli/main.bal`, `commands/*.bal`, `introspect/mysql.bal`, `introspect/postgresql.bal`, `diff/schema_diff.bal`, `diff/sql_generator.bal`

---

### Phase 6 — Testing & Documentation (*ongoing from Phase 2+*)

- **Unit tests**: annotation parsing, query builder → SQL generation (both dialects), filter operators, schema diff algorithm
- **Integration tests**: full CRUD against Dockerized MySQL + PostgreSQL, migration apply/rollback roundtrip, relation queries, transaction rollback
- **Docs**: README quickstart, API reference, example project (User/Post/Category), migration workflow tutorial

---

### Verification

1. Define User/Post/Category models → compiler plugin validates without errors
2. `orm:from(User).where({email: {contains: "test"}}).findMany()` → correct SQL for both MySQL and PostgreSQL
3. CRUD integration against Dockerized MySQL and PostgreSQL — create, read, update, delete, verify
4. Create User with nested Posts → verify FK set, eager load returns populated relations
5. Add column to model → `bal orm migrate dev` → correct ALTER TABLE SQL → apply and verify
6. Point at existing DB → `bal orm db pull` → generates matching Ballerina records
7. Pass invalid field names to `where()` → compiler error at build time

---

### Decisions

- **Schema source of truth**: Ballerina annotated records (not a separate DSL)
- **Query style**: Fluent type-safe builder + raw SQL escape hatch
- **Relations**: Full (1:1, 1:N, M:N) with configurable loading
- **Migrations**: Timestamped SQL files (Prisma-style)
- **Underlying drivers**: Delegates to `ballerinax/mysql` and `ballerinax/postgresql`
- **Transactions**: Ballerina native `transaction` blocks

### Further Considerations

1. **Naming conflict**: Ballerina has an experimental `bal persist` feature — verify this doesn't conflict, or consider extending/building on it instead of starting from scratch.
2. **Streaming large results**: For large result sets, `findMany()` could return `stream<T, error?>` instead of arrays for lazy iteration — decide early as it affects the API surface.
3. **Type mapping**: Need a full Ballerina ↔ SQL type mapping table early (especially `json` ↔ `jsonb`, Ballerina `enum` ↔ MySQL `ENUM`, `decimal` precision, etc.).