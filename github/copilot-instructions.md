# Copilot Instructions — Ballerina ORM

This repository implements a **Prisma-inspired ORM for Ballerina** using annotated record types as the schema source of truth.
Copilot-generated code must follow the architecture, conventions, and development phases described below.

---

# Project Overview

The goal is to build a **type-safe ORM for Ballerina** with:

* Annotated record types as the schema definition
* A fluent, type-safe query builder
* Relation support (1:1, 1:N, M:N)
* Compile-time validation via a compiler plugin
* Migration tooling via a CLI
* Support for **MySQL and PostgreSQL**

The ORM should feel similar to **Prisma** but follow **Ballerina idioms**.

---

# Repository Structure

The project is divided into **three deliverables**.

## 1. Core Library — `thambaru/bal_orm.orm`

Location:

```
modules/orm/
```

Responsibilities:

* Annotation definitions
* Schema parsing
* Query builder
* SQL generation
* Database client
* Connection management
* Relation resolution

The ORM wraps:

* `ballerinax/mysql`
* `ballerinax/postgresql`

Expected structure:

```
modules/orm/
 ├── annotations.bal
 ├── client.bal
 ├── types.bal
 ├── schema/
 │   ├── model.bal
 │   ├── parser.bal
 │   └── validator.bal
 ├── query/
 │   ├── builder.bal
 │   ├── filter.bal
 │   ├── select.bal
 │   ├── include.bal
 │   └── sql_generator.bal
 ├── dialects/
 │   ├── mysql.bal
 │   └── postgresql.bal
 └── connection/
     ├── pool.bal
     └── url_parser.bal
```

---

## 2. Compiler Plugin — `thambaru/bal_orm` compiler plugin

Location:

```
modules/orm-compiler-plugin/
```

Responsibilities:

* Scan for `@orm:Entity` annotated records
* Generate type-safe query types
* Generate CRUD wrappers
* Validate schema relationships at compile time

Structure:

```
modules/orm-compiler-plugin/
 ├── plugin.bal
 ├── analyzer.bal
 ├── generator.bal
 └── type_mapper.bal
```

Generated types include:

* `UserCreateInput`
* `UserUpdateInput`
* `UserWhereInput`
* `UserOrderByInput`
* `UserInclude`

Compiler validation must detect:

* Invalid relation references
* Missing foreign keys
* Type mismatches
* Missing index recommendations

---

## 3. CLI Tool — `bal orm`

Location:

```
modules/orm-cli/
```

Responsibilities:

* Database introspection
* Schema diffing
* SQL migration generation
* Migration execution

Structure:

```
modules/orm-cli/
 ├── main.bal
 ├── commands/
 ├── introspect/
 │   ├── mysql.bal
 │   └── postgresql.bal
 └── diff/
     ├── schema_diff.bal
     └── sql_generator.bal
```

---

# Schema Definition

Schemas are defined using **Ballerina record types with annotations**.

Example:

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

Copilot should prefer **annotated records** instead of creating separate schema DSLs.

---

# Annotation System

The ORM must provide these annotations:

### Entity

```
@orm:Entity
```

Properties:

* `tableName`
* `schema`
* `engine`

### Field Annotations

```
@orm:Id
@orm:AutoIncrement
@orm:Column
@orm:Ignore
@orm:CreatedAt
@orm:UpdatedAt
```

### Indexes

```
@orm:Index
```

Supports:

* single column
* composite
* unique

### Relations

```
@orm:Relation
```

Supported types:

* ONE_TO_ONE
* ONE_TO_MANY
* MANY_TO_MANY

Options:

* `references`
* `foreignKey`
* `joinTable`

---

# Query Builder Design

The ORM uses a **fluent API**.

Example:

```ballerina
User[] users = check orm:from(User)
    .where({email: {contains: "@example.com"}})
    .orderBy({createdAt: orm:DESC})
    .skip(10)
    .take(20)
    .findMany();
```

Create example:

```ballerina
User newUser =
    check orm:from(User)
        .create({email: "a@b.com", name: "Alice"});
```

Supported operations:

* `findMany`
* `findUnique`
* `findFirst`
* `create`
* `createMany`
* `update`
* `updateMany`
* `upsert`
* `delete`
* `deleteMany`
* `count`
* `aggregate`

---

# Filter Operators

Supported operators:

```
equals
not
in
notIn
lt
lte
gt
gte
contains
startsWith
endsWith
isNull
```

Logical operators:

```
AND
OR
NOT
```

Filters must compile into **SQL WHERE clauses**.

---

# Relations

ORM must support:

* eager loading
* relation includes
* nested writes

Example:

```ballerina
orm:from(User)
    .include({posts: true})
    .findMany();
```

Nested writes example:

```ballerina
orm:from(User).create({
    email: "user@test.com",
    posts: {
        create: [
            {title: "Hello"}
        ]
    }
});
```

---

# SQL Generation

Queries should be converted into SQL via a **query AST**.

Dialect modules:

```
modules/orm/dialects/mysql.bal
modules/orm/dialects/postgresql.bal
```

Responsibilities:

* SQL syntax differences
* LIMIT/OFFSET handling
* JSON support
* identifier quoting

---

# ORM Client

The ORM client wraps database drivers.

Example:

```ballerina
orm:Client ormClient = check new ({
    provider: orm:MYSQL,
    host: "localhost",
    port: 3306,
    user: "root",
    password: "password",
    database: "myapp"
});
```

or

```
orm:Client ormClient = check new ({
    url: "postgresql://..."
});
```

Responsibilities:

* connection management
* pooling
* transaction participation

Transactions should integrate with Ballerina:

```
transaction {
    ...
}
```

---

# Raw SQL Support

Provide escape hatches:

```
orm:rawQuery(...)
orm:rawExecute(...)
```

Must support **Ballerina parameterized query templates**.

---

# Migration System

Migrations are SQL-based and timestamped.

Structure:

```
migrations/
 ├── 20260309120000_init/
 │   └── migration.sql
 ├── 20260310143000_add_posts/
 │   └── migration.sql
 └── migration_lock.toml
```

Migration state stored in:

```
_orm_migrations
```

database table.

---

# CLI Commands

The CLI command prefix is:

```
bal orm
```

Supported commands:

| Command                | Description                    |
| ---------------------- | ------------------------------ |
| bal orm init           | Initialize ORM config          |
| bal orm migrate dev    | Generate + apply migration     |
| bal orm migrate deploy | Apply migrations in production |
| bal orm migrate reset  | Reset database                 |
| bal orm migrate status | Show migration status          |
| bal orm db push        | Push schema directly           |
| bal orm db pull        | Generate records from database |
| bal orm generate       | Trigger client generation      |

---

# Testing Requirements

Tests must include:

### Unit Tests

* annotation parsing
* SQL generation
* filter logic
* schema diff algorithm

### Integration Tests

Run against:

* MySQL
* PostgreSQL

Test cases:

* CRUD operations
* nested relations
* transaction rollback
* migration apply/rollback
* eager loading

Use **Docker databases** for integration testing.

---

# Design Decisions

Schema source of truth:

```
Ballerina annotated records
```

Query style:

```
Fluent builder
```

Relations:

```
1:1
1:N
M:N
```

Migrations:

```
SQL-based
timestamped
```

Drivers:

```
ballerinax/mysql
ballerinax/postgresql
```

Transactions:

```
Ballerina native transaction blocks
```

---

# Important Constraints for Copilot

Copilot must:

* Prefer **type-safe APIs**
* Avoid runtime reflection where compile-time generation is possible
* Use **Ballerina idiomatic patterns**
* Maintain **dialect abstraction**
* Keep **query builder immutable**
* Ensure **compile-time validation where possible**

Do not:

* introduce a separate schema DSL
* bypass the compiler plugin for type generation
* tightly couple SQL logic to a specific database

---

# Future Considerations

Potential improvements:

* streaming results (`stream<T>`)
* improved JSON column mapping
* enum mapping
* schema introspection improvements
* compatibility with `bal persist`

These should not block the initial implementation.