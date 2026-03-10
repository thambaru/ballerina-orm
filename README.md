# Ballerina ORM

A Prisma-inspired, type-safe ORM for Ballerina with full relation support, migration tooling, and MySQL + PostgreSQL backends.

## Features

- 🎯 **Type-safe query builder** — Prisma-style fluent API with compile-time safety
- 🔗 **Full relation support** — ONE_TO_ONE, ONE_TO_MANY, MANY_TO_MANY with eager loading
- 📝 **Schema definition via annotations** — Annotated record types as source of truth
- 🔄 **Database migrations** — Automatic schema diffing and SQL generation
- 🗄️ **Multi-database** — MySQL and PostgreSQL support
- 🔒 **Transaction support** — Built on Ballerina's native transaction system
- ⚡ **Connection pooling** — Efficient connection management
- 🛡️ **Compile-time validation** — Catch errors before runtime

## Quick Start

### Installation

Add to your `Ballerina.toml`:

```toml
[dependencies]
ballerinax.orm = "0.1.0"
ballerinax.orm-cli = "0.1.0"
```

Or use Ballerina CLI:

```bash
bal add ballerinax:orm
```

### Define Your Schema

Use annotations to define your data model:

```ballerina
import thambaru/bal_orm.orm;

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
    
    @orm:Relation {relationType: orm:ONE_TO_MANY}
    Post[]? posts;
|};

@orm:Entity {tableName: "posts"}
public type Post record {|
    @orm:Id @orm:AutoIncrement
    int id;
    
    string title;
    string content;
    
    @orm:Column {nullable: false}
    int authorId;
    
    @orm:Relation {
        relationType: orm:MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
    
    @orm:UpdatedAt
    time:Utc updatedAt;
|};
```

### Initialize the Client

```ballerina
import thambaru/bal_orm.orm;

public function main() returns error? {
    // Using connection parameters
    orm:Client db = check new ({
        provider: orm:MYSQL,
        host: "localhost",
        port: 3306,
        user: "root",
        password: "password",
        database: "myapp"
    });
    
    // Or using connection URL
    orm:Client db = check new ({
        url: "postgresql://user:password@localhost:5432/myapp"
    });
    
    // Your code here...
    
    check db.close();
}
```

### Basic CRUD Operations

#### Create

```ballerina
// Create a single record
User newUser = check orm:'from(User).create({
    email: "alice@example.com",
    name: "Alice"
});

// Create multiple records
User[] users = check orm:'from(User).createMany([
    {email: "bob@example.com", name: "Bob"},
    {email: "charlie@example.com", name: "Charlie"}
]);
```

#### Read

```ballerina
// Find by unique identifier
User? user = check orm:'from(User)
    .'where({email: {equals: "alice@example.com"}})
    .findUnique();

// Find first matching record
User? firstAdmin = check orm:'from(User)
    .'where({role: {equals: "ADMIN"}})
    .findFirst();

// Find many with filters
User[] activeUsers = check orm:'from(User)
    .'where({
        status: {equals: "ACTIVE"},
        email: {contains: "@example.com"}
    })
    .orderBy({createdAt: orm:DESC})
    .skip(0)
    .take(10)
    .findMany();
```

#### Update

```ballerina
// Update one
User updated = check orm:'from(User)
    .'where({id: {equals: 1}})
    .update({name: "Alice Smith"});

// Update many
int count = check orm:'from(User)
    .'where({status: {equals: "PENDING"}})
    .updateMany({status: "ACTIVE"});

// Upsert (create or update)
User user = check orm:'from(User).upsert({
    'where: {email: "alice@example.com"},
    create: {email: "alice@example.com", name: "Alice"},
    update: {name: "Alice Updated"}
});
```

#### Delete

```ballerina
// Delete one
User deleted = check orm:'from(User)
    .'where({id: {equals: 1}})
    .delete();

// Delete many
int count = check orm:'from(User)
    .'where({status: {equals: "INACTIVE"}})
    .deleteMany();
```

### Advanced Queries

#### Filter Operators

```ballerina
User[] users = check orm:'from(User)
    .'where({
        // Comparison
        age: {gte: 18, lte: 65},
        
        // String matching
        email: {contains: "@example.com"},
        name: {startsWith: "A", endsWith: "son"},
        
        // List operations
        status: {'in: ["ACTIVE", "PENDING"]},
        role: {notIn: ["BANNED", "DELETED"]},
        
        // Logical operators
        OR: [
            {email: {endsWith: "@example.com"}},
            {email: {endsWith: "@test.com"}}
        ],
        NOT: {
            status: {equals: "DELETED"}
        }
    })
    .findMany();
```

#### Relations & Eager Loading

```ballerina
// Include related records (ONE_TO_MANY)
User? user = check orm:'from(User)
    .include({posts: true})
    .'where({id: {equals: 1}})
    .findUnique();

if user is User && user.posts is Post[] {
    io:println(`User ${user.name} has ${user.posts.length()} posts`);
}

// Include nested relations
Post? post = check orm:'from(Post)
    .include({
        author: true,
        categories: true
    })
    .'where({id: {equals: 1}})
    .findUnique();

// Select specific fields
var userEmails = check orm:'from(User)
    .select({id: true, email: true})
    .findMany();
```

#### Aggregations

```ballerina
// Count
int userCount = check orm:'from(User)
    .'where({status: {equals: "ACTIVE"}})
    .count();

// Aggregations
var stats = check orm:'from(Order)
    .'where({status: {equals: "COMPLETED"}})
    .aggregate({
        sum: ["total"],
        avg: ["total"],
        max: ["total"],
        min: ["total"]
    });

io:println(`Total revenue: ${stats.sum_total}`);
io:println(`Average order: ${stats.avg_total}`);
```

### Transactions

```ballerina
transaction {
    User user = check orm:'from(User).create({
        email: "newuser@example.com",
        name: "New User"
    });
    
    Post post = check orm:'from(Post).create({
        title: "First Post",
        content: "Hello World",
        authorId: user.id
    });
    
    check commit;
}
```

### Raw SQL

For complex queries, use raw SQL:

```ballerina
// Raw query with streaming results
stream<User, error?> userStream = check db.rawQuery(
    "SELECT * FROM users WHERE created_at > ? ORDER BY email",
    "2026-01-01"
);

User[] users = check from User user in userStream select user;

// Raw execution (INSERT, UPDATE, DELETE)
int affectedRows = check db.rawExecute(
    "UPDATE users SET last_login = NOW() WHERE id = ?",
    userId
);
```

## Migrations

### Initialize Migration System

```bash
bal orm init
```

Creates `migrations/` directory and `orm.config.toml`:

```toml
[database]
provider = "mysql"
url = "mysql://root:password@localhost:3306/myapp"
```

### Generate Migrations

```bash
# Generate migration from schema changes
bal orm migrate dev --name add_posts

# Review the generated SQL in migrations/20260309120000_add_posts/migration.sql
```

### Apply Migrations

```bash
# Development: generate + apply
bal orm migrate dev

# Production: apply pending migrations
bal orm migrate deploy

# Check status
bal orm migrate status
```

### Other Migration Commands

```bash
# Reset database (dev only)
bal orm migrate reset

# Push schema without migration file (dev only)
bal orm db push

# Pull schema from existing database
bal orm db pull
```

## Database Support

### MySQL

```ballerina
orm:Client db = check new ({
    provider: orm:MYSQL,
    host: "localhost",
    port: 3306,
    user: "root",
    password: "password",
    database: "myapp",
    connectionPool: {
        maxPoolSize: 10,
        maxLifeTime: 1800
    }
});
```

### PostgreSQL

```ballerina
orm:Client db = check new ({
    provider: orm:POSTGRESQL,
    host: "localhost",
    port: 5432,
    user: "postgres",
    password: "password",
    database: "myapp",
    options: {
        ssl: true
    }
});
```

## Testing

### Run Unit Tests

```bash
bal test --groups unit
```

### Run Integration Tests

```bash
# All integration tests (requires Docker)
./run_integration_tests.sh all

# MySQL only
./run_integration_tests.sh mysql

# PostgreSQL only
./run_integration_tests.sh postgresql
```

## Examples

See the `examples/` directory for complete examples:

- `examples/bal_orm_cli.bal` — Full CLI application example
- `examples/migration_demo.bal` — Migration workflow demonstration

## Documentation

- [API Reference](docs/API_REFERENCE.md) — Complete API documentation
- [Migration Guide](docs/MIGRATION_GUIDE.md) — Detailed migration workflow
- [Compiler Plugin](docs/COMPILER_PLUGIN.md) — Plugin architecture and code generation

## Architecture

1. **Core Library** (`modules/orm/`) — Annotations, query builder, relation resolution, connection management
2. **Compiler Plugin** (`compiler-plugin/`) — Compile-time validation and code generation
3. **CLI Tool** (`modules/orm-cli/`) — Migration engine and schema management

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

Apache License 2.0

## Acknowledgments

Inspired by [Prisma](https://www.prisma.io/) — bringing modern ORM patterns to Ballerina.
