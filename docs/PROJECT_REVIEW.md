# Ballerina ORM — Project Review vs. Plan

> Review date: 2026-03-10
> Compared against: `docs/PLAN.md`

---

## Summary

The project has made solid progress on **Phase 1 (Schema)**, **Phase 2 (Query Builder)**, and **Phase 3 (Client/Connection)** of the plan. The **compiler plugin** and **CLI/migration engine** exist structurally but are largely stubbed out. Several design decisions are well-aligned with the plan; a few areas have notable gaps or issues.

**Overall completion estimate by phase:**

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Core Schema Definition | ~90% complete |
| Phase 2 | Query Builder API | ~80% complete |
| Phase 3 | Database Client & Connection | ~70% complete |
| Phase 4 | Compiler Plugin | ~20% (scaffolded, not functional) |
| Phase 5 | Migration Engine / CLI | ~10% (stubbed, not functional) |
| Phase 6 | Testing & Documentation | ~50% (unit tests good, integration absent) |

---

## Phase 1 — Core Schema Definition

### What's Done Well
- **All planned annotations are implemented**: `@Entity`, `@Id`, `@AutoIncrement`, `@Column`, `@Index`, `@Relation`, `@CreatedAt`, `@UpdatedAt`, `@Ignore` — all present in `annotations.bal`.
- **Schema IR is comprehensive**: `ModelDefinition`, `ColumnDefinition`, `RelationDefinition`, `IndexDefinition`, `SchemaGraph`, `RelationEdge` all match the plan.
- **Schema parser** correctly handles model/field/relation parsing with good error reporting.
- **Schema validator** checks: primary key required, duplicate table names, index field existence, relation target existence, FK/reference field existence, M:N join table requirement, single `@CreatedAt`/`@UpdatedAt` per model.
- **Annotation config types** have appropriate fields matching the plan (`EntityConfig`, `ColumnConfig`, `IndexConfig`, `RelationConfig`).

### Issues & Improvements

1. **`RelationConfig` has redundant fields**: Both `'type` and `relationType` exist for the same purpose. The parser does `relationConfig.'type ?: relationConfig.relationType` as a fallback. This creates API ambiguity — users won't know which to use. **Pick one and remove the other.**

2. **`@Index` annotation is declared as `IndexConfig[]`** (array), but the plan shows it used as a single annotation on the type (e.g., `@orm:Index {columns: ["email"], unique: true}`). Using an array means the annotation syntax would differ from the plan examples. This should be clarified — either use a repeatable single annotation or document the array syntax.

3. **Default engine is hardcoded to `MYSQL`** in `parseModel()` (`rawModel.entity.engine ?: MYSQL`). The plan doesn't specify a default. If the user connects to PostgreSQL but forgets to set the engine on a model, they'll get MySQL-syntax SQL silently. **The engine should be derived from the client config or be required, not silently default.**

4. **`toDefaultTableName` produces naive plurals**: It simply appends `s` (e.g., `Category` → `categorys` instead of `categories`, `Address` → `addresss`). Common ORMs handle this better. At minimum, document this limitation.

5. **`RawSchema` / `RawModel` / `RawField` are input types that users must construct manually** — there's no actual annotation reader that turns Ballerina annotated record types into `RawSchema` at runtime. The plan says "Parse annotations into an intermediate representation" but the actual annotation-to-IR bridge is missing. This is a significant gap — the schema system only works if you build `RawSchema` by hand.

---

## Phase 2 — Query Builder API

### What's Done Well
- **All 12 planned operations implemented**: `findMany`, `findUnique`, `findFirst`, `create`, `createMany`, `update`, `updateMany`, `upsert`, `delete`, `deleteMany`, `count`, `aggregate`.
- **Fluent API matches plan examples**: `orm:from(User).where({...}).orderBy({...}).skip(10).take(20).findMany()`.
- **All planned filter operators implemented**: `equals`, `not`, `in`, `notIn`, `lt`, `lte`, `gt`, `gte`, `contains`, `startsWith`, `endsWith`, `isNull`, `AND`, `OR`, `NOT`.
- **Raw SQL helpers** (`rawQuery`, `rawExecute`) are implemented.
- **Select projection** and **include** input types exist.
- **SQL generation** is dialect-aware with proper identifier quoting and parameter placeholders for both MySQL and PostgreSQL.
- **Test coverage for query builder** is strong — 15 test functions covering all major operations, both dialects, filter operators, aggregation, projection, and logical nesting.

### Issues & Improvements

6. **`upsert` SQL generation is not implemented** — it explicitly returns an error `"QUERY_UPSERT_UNSUPPORTED"`. The test expects this error, so it's acknowledged, but it's a gap vs. the plan. MySQL `INSERT ... ON DUPLICATE KEY UPDATE` and PostgreSQL `INSERT ... ON CONFLICT ... DO UPDATE` are both well-known patterns and should be implemented.

7. **Query builder returns `QueryPlan`, not actual data** — The builder produces a plan object, not results. There's no execution layer that takes a `QueryPlan` + `orm:Client` and returns actual query results. The plan shows `User[] users = check orm:from(User).where({...}).findMany()` returning actual rows, but the current implementation only builds SQL. **This is the biggest functional gap** — the query executor / result mapper is entirely missing.

8. **`include` (eager loading) does not generate JOINs or secondary queries** — The test `testIncludeOneToMany` only asserts the plan has a SELECT/FROM, acknowledging that include doesn't affect SQL generation. The plan specifies eager loading via JOINs or batched queries, which is unimplemented.

9. **Nested writes are not implemented** — The plan shows creating a User with nested Posts atomically. There's no support for this in the query builder or SQL generator.

10. **`contains` filter has SQL injection risk in LIKE patterns** — The `contains`, `startsWith`, and `endsWith` operators embed user strings directly into LIKE patterns without escaping `%` or `_` wildcard characters in the value. For example, `{contains: "100%"}` would generate `LIKE '%100%%'`, which doesn't match the intent. Values should escape LIKE-special characters.

11. **`UPDATE ... LIMIT 1` is not valid PostgreSQL** — `buildUpdateSql` appends `LIMIT 1` for single-row updates regardless of dialect. PostgreSQL does not support `LIMIT` in `UPDATE` statements. Similarly, `DELETE ... LIMIT 1` is MySQL-only. PostgreSQL uses `DELETE FROM ... WHERE ctid IN (SELECT ctid ... LIMIT 1)` or similar. This will fail at runtime against PostgreSQL.

12. **`joinWithSeparator` uses an undeclared variable** — The function body uses `out = ""` without a `string` declaration. This should be `string out = ""`. If this compiles, it's relying on Ballerina's implicit behavior, but it's unclear and potentially a bug.

13. **`extractModelName` from `typedesc` is fragile** — It calls `modelType.toString()` and parses the string representation. This is undocumented behavior and may break across Ballerina versions. The plan acknowledges this implicitly by relying on the compiler plugin for type safety, but the runtime path should be more robust.

---

## Phase 3 — Database Client & Connection

### What's Done Well
- **`orm:Client`** wraps both `mysql:Client` and `postgresql:Client` correctly.
- **Connection URL parsing** is thorough — handles schemes, auth, host/port, IPv6, database path, query params.
- **Config normalization** merges URL and explicit config with proper precedence and conflict detection.
- **Connection pool** support is delegated to `ballerina/sql` as planned.
- **Client tests** cover URL parsing, config normalization, and provider mismatch detection.

### Issues & Improvements

14. **No transaction support** — The plan calls for Ballerina native `transaction {}` block integration. There's no indication the ORM client participates in transactions. The `orm:Client` exposes `getNativeClient()` which could be used manually, but the plan specifies automatic participation.

15. **No query execution methods on `orm:Client`** — The client only has `getConfig()`, `getNativeClient()`, and `close()`. There's no `execute(QueryPlan)`, `query(QueryPlan)`, or similar method. **The client can't actually run queries through the ORM layer** — users would have to get the native client and use raw SQL.

16. **`close()` is `isolated` but the class isn't** — The `close` function is marked `isolated` but the `Client` class is not an isolated class, and `self.provider` / `self.nativeClient` aren't isolated-compatible. This may cause compile warnings or errors depending on Ballerina version.

17. **Password in `ParsedConnectionUrl` is stored as plain `string?`** — While this is common, the connection URL (which contains credentials) gets fully parsed and stored in memory. The plan doesn't mention security, but consider at least not storing the raw password longer than necessary.

---

## Phase 4 — Compiler Plugin

### What's Done
- **Ballerina-side scaffolding is complete**: `plugin.bal` has `CompilerPlugin` class with `scan()` and `run()` pipeline, `analyzer.bal` has schema analysis with diagnostics, `generator.bal` generates typed input records and CRUD wrappers.
- **Java-side plugin exists**: `OrmCompilerPlugin.java`, `OrmCodeAnalyzer.java`, `OrmCodeGenerator.java` with proper ServiceLoader registration.
- **Analyzer detects**: relation type mismatches, missing FK indexes (warning), incomplete relation key definitions, FK/reference count mismatches.
- **Generator produces**: `*CreateInput`, `*UpdateInput`, `*WhereInput`, `*OrderByInput`, `*Include` types and 5 CRUD wrappers per model.

### Issues & Improvements

18. **Java analyzer and generator are empty stubs** — Both `OrmCodeAnalyzer.init()` and `OrmCodeGenerator.init()` are TODO-only. The actual Ballerina compiler plugin does **nothing** at compile time. The Ballerina-side `CompilerPlugin` class works as a library function (call `executeCompilerPlugin()` manually), but the real compiler integration that fires automatically during `bal build` is not implemented.

19. **Generated `WhereInput` and `OrderByInput` are `map<anydata>` / `map<SortDirection>`** — These aren't actually type-safe. The plan says the compiler plugin should generate field-specific typed filter records. Using `map<anydata>` means any field name is accepted at compile time, defeating the purpose of type-safe queries.

20. **Generated CRUD wrappers accept generic `map<anydata>` for data** — For example, `userCreate(UserCreateInput payload)` calls `fromModel("User").create(payload)`, but `create()` accepts `map<anydata>`. The `UserCreateInput` record gives type safety at the call site, but the generated code passes it to a method that accepts anything. If Ballerina allows passing a closed record to `map<anydata>`, this works, but it's a half-measure.

21. **No generated source files** — The generator builds strings representing Ballerina record types, but these are never written to actual `.bal` files. They exist only as in-memory `GeneratedTypeSource` records. The plan calls for the compiler plugin to produce generated files that get compiled.

---

## Phase 5 — Migration Engine / CLI

### What's Done
- **Type definitions are solid**: `Migration`, `IntrospectedSchema`, `IntrospectedTable`, `IntrospectedColumn`, `IntrospectedIndex`, `IntrospectedForeignKey`, `SchemaDiff`, `SchemaDiffItem`, `MigrationAction`, `CliConfig` — all well-defined.
- **Command handlers are scaffolded**: `handleInitCommand`, `handleMigrateDevCommand`, `handleMigrateDeployCommand`, `handleMigrateResetCommand`, `handleMigrateStatusCommand`, `handleDbPushCommand`, `handleDbPullCommand`, `handleGenerateCommand` — all present.
- **Schema diff function** exists and detects added/removed tables.
- **SQL generator** can produce basic `CREATE TABLE` and `DROP TABLE` statements.
- **Docker setup** for test databases is ready.

### Issues & Improvements

22. **Almost everything is a stub** — Every command handler is a series of `io:println` + `// TODO` comments. None of the core functionality works:
   - `introspectMysql` and `introspectPostgresql` return empty schemas
   - `listMigrations` returns an empty array
   - `getAppliedMigrations` returns an empty array
   - `recordMigrationApplied` does nothing
   - `createMigrationLock` does nothing
   - `initProject` only prints a message

23. **No actual `main()` entry point for CLI** — The plan specifies a `bal orm` CLI tool. There's no `main.bal` with command parsing (the plan lists `modules/orm-cli/main.bal`). The commands module would need a dispatcher.

24. **`generateCreateTableSql` ignores columns** — It accepts columns but ignores them: `_ = columns; _ = provider;` and returns `CREATE TABLE tableName ();`. This is a skeleton.

25. **Schema diff only detects table-level adds/removes** — Column-level changes (add/modify/drop column), index changes, and constraint changes are not detected. The plan says "detect added/removed/renamed tables, columns, indexes, relations."

26. **Migration tests are conceptual, not functional** — They test hardcoded string patterns rather than actual migration functions. For example, `testCreateTableSqlFormat()` tests a manually written SQL string, not output from the SQL generator.

27. **No migration file I/O** — There's no filesystem interaction to read/write migration `.sql` files or `migration_lock.toml`. The `createMigrationFile` function creates an in-memory record.

---

## Phase 6 — Testing & Documentation

### What's Done Well
- **Unit tests for schema parsing**: 3 tests covering happy path, relation validation failure, index validation failure.
- **Unit tests for query builder**: 15 tests covering all operations, both dialects, all filter operators, projections, aggregations, logical nesting.
- **Unit tests for client/connection**: 4 tests covering URL parsing, config normalization, provider mismatch.
- **Unit tests for compiler plugin**: 3 tests covering artifact generation, type mismatch detection, FK index warnings.
- **Documentation**: `API_REFERENCE.md`, `COMPILER_PLUGIN.md`, `MIGRATION_GUIDE.md` are all substantial and well-written.
- **Complete example**: `complete_blog_example.bal` demonstrates a full 5-entity blog application.
- **Docker Compose** config for test databases is properly set up.
- **Integration test runner** shell script with proper setup/teardown.

### Issues & Improvements

28. **Integration tests are smoke-only** — Both `integration_mysql_test.bal` and `integration_postgresql_test.bal` contain a single `test:assertTrue(true)`. No actual database operations are tested. The plan specifies CRUD operations, nested relations, transaction rollback, migration apply/rollback, and eager loading.

29. **`lib_test.bal` tests the default template** — The root project file `bal_orm.bal` still contains the default `hello()` function from `bal new`. The root test file tests this function. Neither contributes to the ORM.

30. **Migration tests (`migration_test.bal`) don't use the actual code** — They assert properties of hand-written strings rather than calling `generateMigrationSql`, `diffSchemas`, `generateCreateTableSql`, etc.

31. **No tests for `type_mapper.bal`** — Functions like `areRelationTypesCompatible`, `createInputFieldType`, `updateInputFieldType`, `emitFieldIdentifier` have no dedicated test coverage.

---

## Structural Discrepancies vs. Plan

32. **File organization differs from plan** — The plan specifies subdirectories (`schema/`, `query/`, `dialects/`, `connection/`), but the actual layout uses flat files with prefixed names (`schema_model.bal`, `query_builder.bal`, `dialect_mysql.bal`, `connection_pool.bal`). This is functionally equivalent but doesn't match the documented structure.

33. **`modules/orm-compiler-plugin/` doesn't exist** — The plan lists Ballerina-side compiler plugin files under `modules/orm-compiler-plugin/`. Instead, the plugin scaffolding is **inside** `modules/orm/` (as `plugin.bal`, `analyzer.bal`, `generator.bal`, `type_mapper.bal`), with the Java plugin in a separate `compiler-plugin/` Gradle project. This is actually a reasonable adaptation for Ballerina's module system.

34. **No `bal orm` CLI invocation mechanism** — The plan describes CLI commands (`bal orm init`, `bal orm migrate dev`, etc.), but there's no Ballerina tool command registration or `main` function to invoke them.

---

## Security Concerns

35. **LIKE pattern injection** (mentioned in #10) — User-supplied values in `contains`/`startsWith`/`endsWith` are not escaped for SQL LIKE wildcards (`%`, `_`).

36. **SQL identifier injection** — `quoteIdentifier` wraps names in backticks or double quotes but does **not check or escape** the identifier itself. If a model name or field name contained a backtick or double quote, it could break or inject SQL. Identifiers should have special characters escaped.

---

## Priority Recommendations

### Critical (blocks basic usability)
1. **Implement query execution** — Connect `QueryPlan` → `orm:Client` → execute SQL → return typed results (#7, #15)
2. **Fix PostgreSQL `LIMIT` in UPDATE/DELETE** (#11) — Will fail at runtime
3. **Escape LIKE wildcards** in filter values (#10) — Correctness issue
4. **Escape SQL identifiers** (#36) — Security issue

### High Priority (core features per plan)
5. Implement `upsert` SQL generation (#6)
6. Implement eager loading (`include` → JOINs/batched queries) (#8)
7. Implement the Java compiler plugin analyzer/generator (#18)
8. Wire the engine from client config rather than defaulting to MySQL (#3)
9. Remove `RelationConfig.relationType` duplication (#1)

### Medium Priority (completes planned features)
10. Implement database introspection for MySQL and PostgreSQL (#22)
11. Implement schema diff for columns/indexes/constraints (#25)
12. Implement migration file I/O (#27)
13. Implement nested writes (#9)
14. Add transaction participation (#14)
15. Write real integration tests (#28)

### Low Priority (polish)
16. Clean up default `hello()` code in `bal_orm.bal` (#29)
17. Add `type_mapper.bal` tests (#31)
18. Improve plural table name generation (#4)
19. Add CLI entry point with command dispatcher (#23, #34)
20. Write functional migration tests (#26, #30)
