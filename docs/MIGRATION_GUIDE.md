# Migration Guide

Complete guide to database migrations with Ballerina ORM.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Development Workflow](#development-workflow)
- [Production Workflow](#production-workflow)
- [Migration Commands](#migration-commands)
- [Schema Introspection](#schema-introspection)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Ballerina ORM uses a **schema-first** approach where:

1. You define your data model using annotated Ballerina record types
2. The migration engine compares your schema with the database
3. SQL migrations are auto-generated to sync the database with your schema

### Key Concepts

- **Source of Truth**: Annotated Ballerina records
- **Migration Files**: Timestamped SQL files in `migrations/` directory
- **Migration History**: Tracked in `_orm_migrations` table
- **Environments**: Development (auto-apply) vs Production (manual review)

---

## Setup

### Initialize Migration System

```bash
cd your-project
bal orm init
```

Creates:
- `migrations/` directory — Stores migration files
- `orm.config.toml` — Database connection configuration
- `.migration_lock.toml` — Ensures single migration process

### Configure Database Connection

Edit `orm.config.toml`:

```toml
[database]
provider = "mysql"
url = "mysql://root:password@localhost:3306/myapp"

# Or use individual parameters
# provider = "postgresql"
# host = "localhost"
# port = 5432
# user = "postgres"
# password = "password"
# database = "myapp"
```

### Environment-Specific Configurations

Create multiple config files:

```bash
orm.config.dev.toml
orm.config.staging.toml
orm.config.prod.toml
```

Use with:
```bash
bal orm migrate deploy --env prod
```

---

## Development Workflow

### Step 1: Define Your Schema

Create or modify your data models:

```ballerina
// modules/orm/models.bal

@Entity {tableName: "users"}
@Index {columns: ["email"], unique: true}
public type User record {|
    @Id @AutoIncrement
    int id;
    
    @Column {length: 255, nullable: false}
    string email;
    
    string name;
    
    @CreatedAt
    time:Utc createdAt;
|};

@Entity {tableName: "posts"}
public type Post record {|
    @Id @AutoIncrement
    int id;
    
    string title;
    
    @Column {type: "TEXT"}
    string content;
    
    @Column {nullable: false}
    int authorId;
    
    @Relation {
        relationType: MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
    
    @UpdatedAt
    time:Utc updatedAt;
|};
```

### Step 2: Generate Migration

```bash
bal orm migrate dev --name add_posts
```

This will:
1. Analyze your schema
2. Introspect the current database state
3. Generate SQL to sync database with schema
4. Apply the migration immediately (development mode)

### Step 3: Review Generated SQL

Migration file created at `migrations/20260309120000_add_posts/migration.sql`:

```sql
-- CreateTable
CREATE TABLE `posts` (
    `id` INTEGER NOT NULL AUTO_INCREMENT,
    `title` VARCHAR(191) NOT NULL,
    `content` TEXT NOT NULL,
    `author_id` INTEGER NOT NULL,
    `updated_at` DATETIME(3) NOT NULL,
    
    PRIMARY KEY (`id`),
    INDEX `idx_author_id` (`author_id`),
    CONSTRAINT `fk_posts_author` 
        FOREIGN KEY (`author_id`) 
        REFERENCES `users`(`id`) 
        ON DELETE RESTRICT 
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Step 4: Iterate

Make schema changes and run `bal orm migrate dev` again. The migration engine is smart enough to:
- Add new fields/tables
- Modify existing fields (type, length, nullability)
- Drop removed fields/tables
- Create/drop indexes
- Manage foreign key constraints

---

## Production Workflow

### Step 1: Create Migration (Don't Apply)

```bash
bal orm migrate create --name add_user_roles
```

This generates the migration file **without** applying it.

### Step 2: Review Migration

Carefully review the generated SQL:

```bash
cat migrations/20260309130000_add_user_roles/migration.sql
```

**Check for:**
- Data loss operations (DROP COLUMN, DROP TABLE)
- Performance impacts (adding indexes on large tables)
- Breaking changes (NOT NULL on existing columns)

### Step 3: Test in Staging

```bash
bal orm migrate deploy --env staging
```

### Step 4: Deploy to Production

```bash
bal orm migrate deploy --env prod
```

This applies **only pending migrations** that haven't been applied yet.

---

## Migration Commands

### bal orm init

Initializes migration system.

```bash
bal orm init
```

Options:
- `--database-url <url>` — Database connection URL
- `--provider <mysql|postgresql>` — Database provider

### bal orm migrate dev

Generates and applies migration (development).

```bash
bal orm migrate dev --name <migration_name>
```

Options:
- `--name <name>` — Migration name (required)
- `--create-only` — Generate without applying

### bal orm migrate create

Generates migration without applying (production).

```bash
bal orm migrate create --name <migration_name>
```

### bal orm migrate deploy

Applies pending migrations (production).

```bash
bal orm migrate deploy
```

Options:
- `--env <environment>` — Environment config to use

### bal orm migrate status

Shows migration status.

```bash
bal orm migrate status
```

Output:
```
Applied migrations:
  ✓ 20260309120000_init
  ✓ 20260309130000_add_posts

Pending migrations:
  - 20260309140000_add_categories
  - 20260309150000_add_user_roles
```

### bal orm migrate resolve

Marks a migration as applied without running it.

```bash
bal orm migrate resolve --applied <migration_name>
bal orm migrate resolve --rolled-back <migration_name>
```

### bal orm migrate reset

**⚠️ Development only** — Resets database and reapplies all migrations.

```bash
bal orm migrate reset
```

Drops all tables and reapplies migrations from scratch.

### bal orm db push

**⚠️ Development only** — Pushes schema changes directly without creating migration file.

```bash
bal orm db push
```

Useful for rapid prototyping, but **not recommended** for production use.

### bal orm db pull

Introspects existing database and generates Ballerina schema.

```bash
bal orm db pull --output models.bal
```

Creates annotated record types from existing database schema.

---

## Schema Introspection

### Pull Schema from Existing Database

If you have an existing database:

```bash
bal orm db pull --output modules/orm/generated_models.bal
```

Generates:

```ballerina
@Entity {tableName: "users"}
@Index {columns: ["email"], unique: true}
public type User record {|
    @Id @AutoIncrement
    int id;
    
    @Column {length: 255, nullable: false}
    string email;
    
    string name;
    
    time:Utc createdAt;
|};
```

### Customize Generated Schema

Edit the generated file to:
- Add relations
- Rename fields (while preserving column mappings)
- Add custom validations
- Mark fields with `@CreatedAt`, `@UpdatedAt`

---

## Common Migration Scenarios

### Adding a New Table

1. Define the record type:
```ballerina
@Entity {tableName: "categories"}
public type Category record {|
    @Id @AutoIncrement
    int id;
    
    @Column {length: 100, unique: true}
    string name;
    
    string? description;
|};
```

2. Generate migration:
```bash
bal orm migrate dev --name add_categories
```

### Adding a Column

1. Add field to record:
```ballerina
@Entity {tableName: "users"}
public type User record {|
    @Id @AutoIncrement
    int id;
    string email;
    string name;
    
    // New field
    @Column {length: 20, nullable: true}
    string? phoneNumber;
|};
```

2. Generate migration:
```bash
bal orm migrate dev --name add_user_phone
```

Generated SQL:
```sql
ALTER TABLE `users` ADD COLUMN `phone_number` VARCHAR(20) NULL;
```

### Modifying a Column

```ballerina
// Change email length from 255 to 320
@Column {length: 320, nullable: false}
string email;
```

```bash
bal orm migrate dev --name increase_email_length
```

Generated SQL (MySQL):
```sql
ALTER TABLE `users` MODIFY COLUMN `email` VARCHAR(320) NOT NULL;
```

Generated SQL (PostgreSQL):
```sql
ALTER TABLE "users" ALTER COLUMN "email" TYPE VARCHAR(320);
```

### Removing a Column

1. Remove field from record
2. Generate migration:
```bash
bal orm migrate dev --name remove_old_field
```

Generated SQL:
```sql
ALTER TABLE `users` DROP COLUMN `old_field`;
```

### Adding an Index

```ballerina
@Entity {tableName: "users"}
@Index {columns: ["email"], unique: true}
@Index {columns: ["status", "createdAt"]}  // New composite index
public type User record {|
    // ...
|};
```

```bash
bal orm migrate dev --name add_status_index
```

### Renaming a Table

Use `@Column` to preserve database column name:

```ballerina
// Old
@Entity {tableName: "user_accounts"}
type UserAccount record {|...|};

// New (rename in code but keep DB name)
@Entity {tableName: "user_accounts"}
type User record {|...|};

// Or rename in DB too
@Entity {tableName: "users"}
type User record {|...|};
```

For DB rename, manually edit migration:
```sql
ALTER TABLE `user_accounts` RENAME TO `users`;
```

### Creating a Foreign Key

1. Define relation:
```ballerina
@Entity {tableName: "posts"}
public type Post record {|
    @Id int id;
    
    @Column {nullable: false}
    int authorId;
    
    @Relation {
        relationType: MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
|};
```

2. Generate migration:
```bash
bal orm migrate dev --name add_post_author_fk
```

### Many-to-Many Relationship

```ballerina
@Entity {tableName: "posts"}
public type Post record {|
    @Id int id;
    
    @Relation {
        relationType: MANY_TO_MANY,
        joinTable: "post_categories"
    }
    Category[]? categories;
|};

@Entity {tableName: "categories"}
public type Category record {|
    @Id int id;
    string name;
|};
```

Generates join table:
```sql
CREATE TABLE `post_categories` (
    `post_id` INTEGER NOT NULL,
    `category_id` INTEGER NOT NULL,
    
    PRIMARY KEY (`post_id`, `category_id`),
    INDEX `idx_post_id` (`post_id`),
    INDEX `idx_category_id` (`category_id`),
    CONSTRAINT `fk_post_categories_post` 
        FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_post_categories_category` 
        FOREIGN KEY (`category_id`) REFERENCES `categories`(`id`) ON DELETE CASCADE
);
```

---

## Best Practices

### 1. Name Migrations Descriptively

```bash
✅ bal orm migrate dev --name add_user_authentication
✅ bal orm migrate dev --name create_order_tables
✅ bal orm migrate dev --name add_index_to_email

❌ bal orm migrate dev --name update
❌ bal orm migrate dev --name migration1
```

### 2. Review Before Production Deploy

Always review generated SQL before deploying to production:

```bash
# Generate migration
bal orm migrate create --name add_indexes

# Review
cat migrations/20260309120000_add_indexes/migration.sql

# Test in staging
bal orm migrate deploy --env staging

# Deploy to production
bal orm migrate deploy --env prod
```

### 3. Handle Data Migrations

For complex data transformations, edit the migration file:

```sql
-- Auto-generated
ALTER TABLE `users` ADD COLUMN `full_name` VARCHAR(255) NULL;

-- Add custom data migration
UPDATE `users` SET `full_name` = CONCAT(`first_name`, ' ', `last_name`);

-- Then make it non-nullable
ALTER TABLE `users` MODIFY COLUMN `full_name` VARCHAR(255) NOT NULL;
```

### 4. Use Transactions

Wrap migrations in transactions (PostgreSQL):

```sql
BEGIN;

-- Migration statements here
ALTER TABLE ...;

COMMIT;
```

### 5. Backup Before Major Migrations

Always backup production database before running migrations:

```bash
# MySQL
mysqldump -u user -p database > backup_$(date +%Y%m%d_%H%M%S).sql

# PostgreSQL
pg_dump -U user database > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 6. Test Rollback Strategy

For critical migrations, create a rollback migration:

```sql
-- migration.sql (forward)
ALTER TABLE `users` ADD COLUMN `new_field` VARCHAR(255);

-- rollback.sql (backward)
ALTER TABLE `users` DROP COLUMN `new_field`;
```

### 7. Avoid Destructive Changes

Be careful with:
- `DROP TABLE` — Data loss
- `DROP COLUMN` — Data loss
- `ALTER COLUMN ... NOT NULL` — May fail if existing NULL values
- Changing column types — Potential data truncation

---

## Troubleshooting

### Migration Already Applied

```
Error: Migration 20260309120000_init has already been applied
```

**Solution:** Use `bal orm migrate status` to check applied migrations. Skip or use `bal orm migrate resolve`.

### Migration Lock

```
Error: Migration lock is held by another process
```

**Solution:** 
1. Ensure no other migration process is running
2. Delete `.migration_lock.toml` if stuck
3. Retry migration

### Schema Out of Sync

```
Error: Database schema does not match expected state
```

**Solution:**
1. Run `bal orm migrate status` to see discrepancies
2. Use `bal orm migrate resolve --applied <name>` to mark migrations
3. Or use `bal orm db push` (dev only) to force sync

### Foreign Key Constraint Failure

```
Error: Cannot add foreign key constraint
```

**Solution:**
1. Ensure referenced table exists
2. Check referencing column type matches referenced column
3. Apply migrations in correct order

### Cannot Drop Column with Data

```
Error: Cannot drop column 'email' - data would be lost
```

**Solution:**
1. Review if column should really be dropped
2. Migrate data to another column first
3. Use `--force-data-loss` flag (with extreme caution)

---

## Migration History Table

Ballerina ORM tracks migrations in `_orm_migrations` table:

```sql
CREATE TABLE `_orm_migrations` (
    `id` INTEGER AUTO_INCREMENT PRIMARY KEY,
    `migration_name` VARCHAR(255) NOT NULL UNIQUE,
    `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Manually Mark Migration as Applied

```bash
bal orm migrate resolve --applied 20260309120000_init
```

Inserts into `_orm_migrations` without running SQL.

### Manually Mark Migration as Rolled Back

```bash
bal orm migrate resolve --rolled-back 20260309120000_init
```

Removes from `_orm_migrations` without running rollback SQL.

---

## Next Steps

- [API Reference](API_REFERENCE.md) — Complete API documentation
- [Examples](../examples/) — See migration examples in action
