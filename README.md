# Ballerina ORM

A Prisma-inspired, type-safe ORM for Ballerina with full relation support and MySQL + PostgreSQL backends.

## Features

- 🎯 **Type-safe query builder** — Prisma-style fluent API with compile-time safety
- 🔗 **Full relation support** — ONE_TO_ONE, ONE_TO_MANY, MANY_TO_MANY with eager loading
- 📝 **Schema definition via annotations** — Annotated record types as source of truth
- 🗄️ **Multi-database** — MySQL and PostgreSQL support
- 🔒 **Transaction support** — Built on Ballerina's native transaction system
- ⚡ **Connection pooling** — Efficient connection management
- 🛡️ **Compile-time validation** — Catch errors before runtime

## Quick Start

### Installation

Add to your `Ballerina.toml`:

```toml
[dependencies]
thambaru.bal_orm = "0.1.0"
```

Or use Ballerina CLI:

```bash
bal add thambaru:bal_orm
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
    
    @orm:Relation {'type: orm:ONE_TO_MANY}
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
        'type: orm:MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
    
    @orm:UpdatedAt
    time:Utc updatedAt;
|};
```

When you build a normalized `orm:RawSchema` manually instead of relying on compiler tooling, set `defaultEngine` on the schema or `engine` on each model. The parser no longer falls back to MySQL implicitly.

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
User newUser = check db.'from(User).create({
    email: "alice@example.com",
    name: "Alice"
});

// Create multiple records
User[] users = check db.'from(User).createMany([
    {email: "bob@example.com", name: "Bob"},
    {email: "charlie@example.com", name: "Charlie"}
]);
```

#### Read

```ballerina
// Find by unique identifier
User? user = check db.'from(User)
    .'where({email: {equals: "alice@example.com"}})
    .findUnique();

// Find first matching record
User? firstAdmin = check db.'from(User)
    .'where({role: {equals: "ADMIN"}})
    .findFirst();

// Find many with filters
User[] activeUsers = check db.'from(User)
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
User updated = check db.'from(User)
    .'where({id: {equals: 1}})
    .update({name: "Alice Smith"});

// Update many
int count = check db.'from(User)
    .'where({status: {equals: "PENDING"}})
    .updateMany({status: "ACTIVE"});

// Upsert (create or update)
User user = check db.'from(User).upsert(
    {email: "alice@example.com", name: "Alice"},
    {name: "Alice Updated"}
);
```

#### Delete

```ballerina
// Delete one
User deleted = check db.'from(User)
    .'where({id: {equals: 1}})
    .delete();

// Delete many
int count = check db.'from(User)
    .'where({status: {equals: "INACTIVE"}})
    .deleteMany();
```

### Advanced Queries

#### Filter Operators

```ballerina
User[] users = check db.'from(User)
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
User? user = check db.'from(User)
    .include({posts: true})
    .'where({id: {equals: 1}})
    .findUnique();

if user is User && user.posts is Post[] {
    io:println(`User ${user.name} has ${user.posts.length()} posts`);
}

// Include nested relations
Post? post = check db.'from(Post)
    .include({
        author: true,
        categories: true
    })
    .'where({id: {equals: 1}})
    .findUnique();

// Select specific fields
var userEmails = check db.'from(User)
    .select({id: true, email: true})
    .findMany();
```

#### Aggregations

```ballerina
// Count
int userCount = check db.'from(User)
    .'where({status: {equals: "ACTIVE"}})
    .count();

// Aggregations
var stats = check db.'from(Order)
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
    User user = check db.'from(User).create({
        email: "newuser@example.com",
        name: "New User"
    });
    
    Post post = check db.'from(Post).create({
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
// Raw query with streaming results (rowType inferred from assignment context)
stream<User, error?> userStream = check db.rawQuery(
    "SELECT * FROM users WHERE created_at > ? ORDER BY email",
    ["2026-01-01"]
);

User[] users = check from User user in userStream select user;

// Raw execution (INSERT, UPDATE, DELETE) — returns affected row count
int affectedRows = check db.rawExecute(
    "UPDATE users SET last_login = NOW() WHERE id = ?",
    [userId]
);
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

- `examples/complete_blog_example.bal` — End-to-end ORM usage with entities and relations

## Documentation

- [API Reference](docs/API_REFERENCE.md) — Complete API documentation
- [Compiler Plugin](docs/COMPILER_PLUGIN.md) — Plugin architecture and code generation

## Architecture

1. **Core Library** (`modules/orm/`) — Annotations, query builder, relation resolution, connection management
2. **Compiler Plugin** (`compiler-plugin/`) — Compile-time validation and code generation

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

Apache License 2.0

## Acknowledgments

Inspired by [Prisma](https://www.prisma.io/) — bringing modern ORM patterns to Ballerina.
