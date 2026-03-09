# API Reference

Complete API documentation for Ballerina ORM.

## Table of Contents

- [Annotations](#annotations)
- [Client](#client)
- [Query Builder](#query-builder)
- [Filter Operators](#filter-operators)
- [Relation Operations](#relation-operations)
- [Transactions](#transactions)
- [Raw SQL](#raw-sql)
- [Types](#types)

---

## Annotations

### @Entity

Marks a record type as a database entity (table).

```ballerina
@Entity {
    tableName: string,  // Table name in database
    schema?: string,    // Schema name (PostgreSQL only)
    engine?: Engine     // Storage engine (MySQL only)
}
```

**Example:**
```ballerina
@Entity {tableName: "users"}
public type User record {|
    // fields...
|};
```

### @Id

Marks a field as the primary key.

```ballerina
@Id
int id;
```

### @AutoIncrement

Marks a field as auto-incrementing (typically used with @Id).

```ballerina
@Id @AutoIncrement
int id;
```

### @Column

Configures column-specific properties.

```ballerina
@Column {
    name?: string,         // Column name (defaults to field name)
    type?: string,         // SQL type override
    length?: int,          // Length for VARCHAR/CHAR
    precision?: int,       // Precision for DECIMAL
    scale?: int,           // Scale for DECIMAL
    nullable?: boolean,    // Whether column allows NULL (default: true)
    unique?: boolean,      // Whether column has UNIQUE constraint
    default?: string       // Default value expression
}
```

**Example:**
```ballerina
@Column {length: 255, nullable: false, unique: true}
string email;
```

### @Relation

Defines a relationship between entities.

```ballerina
@Relation {
    relationType: RelationType,  // ONE_TO_ONE, ONE_TO_MANY, MANY_TO_ONE, MANY_TO_MANY
    references?: string[],       // Referenced field(s) in target model
    foreignKey?: string[],       // Foreign key field(s) in current model
    joinTable?: string          // Join table name (for MANY_TO_MANY)
}
```

**Examples:**
```ballerina
// ONE_TO_MANY
@Relation {relationType: ONE_TO_MANY}
Post[]? posts;

// MANY_TO_ONE
@Relation {
    relationType: MANY_TO_ONE,
    references: ["id"],
    foreignKey: ["authorId"]
}
User? author;

// MANY_TO_MANY
@Relation {
    relationType: MANY_TO_MANY,
    joinTable: "post_categories"
}
Category[]? categories;
```

### @Index

Creates an index on specified columns.

```ballerina
@Index {
    columns: string[],   // Columns to index
    unique?: boolean,    // Whether index is unique (default: false)
    name?: string       // Index name (auto-generated if not provided)
}
```

**Example:**
```ballerina
@Entity {tableName: "users"}
@Index {columns: ["email"], unique: true}
@Index {columns: ["status", "createdAt"]}
public type User record {|
    // fields...
|};
```

### @CreatedAt

Auto-populates field with creation timestamp.

```ballerina
@CreatedAt
time:Utc createdAt;
```

### @UpdatedAt

Auto-updates field on every update operation.

```ballerina
@UpdatedAt
time:Utc updatedAt;
```

### @Ignore

Excludes field from database mapping.

```ballerina
@Ignore
string computedField;
```

---

## Client

### Constructor

```ballerina
public isolated function init(ClientConfig config) returns Error?
```

**Parameters:**

```ballerina
type ClientConfig record {|
    # Database provider
    Provider provider?;
    
    # Connection URL (overrides individual parameters)
    string url?;
    
    # Database host
    string host?;
    
    # Database port
    int port?;
    
    # Database user
    string user?;
    
    # Database password
    string password?;
    
    # Database name
    string database?;
    
    # Connection pool configuration
    ConnectionPoolConfig connectionPool?;
    
    # Additional options (provider-specific)
    map<anydata> options?;
|};
```

**Example:**
```ballerina
orm:Client client = check new ({
    provider: orm:MYSQL,
    host: "localhost",
    port: 3306,
    user: "root",
    password: "password",
    database: "myapp"
});
```

### client.close()

```ballerina
public isolated function close() returns Error?
```

Closes the database connection and releases resources.

**Example:**
```ballerina
check client.close();
```

### client.rawQuery()

```ballerina
public isolated function rawQuery(string query, anydata... params) 
    returns stream<record {}, error?>|Error
```

Executes a raw SQL query and returns a stream of results.

**Example:**
```ballerina
stream<User, error?> users = check client.rawQuery(
    "SELECT * FROM users WHERE age > ?",
    18
);
```

### client.rawExecute()

```ballerina
public isolated function rawExecute(string query, anydata... params) 
    returns int|Error
```

Executes a raw SQL statement (INSERT, UPDATE, DELETE) and returns affected rows.

**Example:**
```ballerina
int affected = check client.rawExecute(
    "UPDATE users SET status = ? WHERE id = ?",
    "ACTIVE",
    userId
);
```

---

## Query Builder

### orm:from()

```ballerina
public function 'from(typedesc<record {}> model) returns QueryBuilder
```

Creates a query builder for the specified model.

**Example:**
```ballerina
User[] users = check orm:'from(User).findMany();
```

---

## Query Methods

### findUnique()

```ballerina
public function findUnique() returns Model?|Error
```

Finds a single record by unique constraint. Returns `()` if not found.

**Example:**
```ballerina
User? user = check orm:'from(User)
    .'where({email: {equals: "alice@example.com"}})
    .findUnique();
```

### findFirst()

```ballerina
public function findFirst() returns Model?|Error
```

Finds the first matching record. Returns `()` if not found.

**Example:**
```ballerina
User? admin = check orm:'from(User)
    .'where({role: {equals: "ADMIN"}})
    .orderBy({createdAt: DESC})
    .findFirst();
```

### findMany()

```ballerina
public function findMany() returns Model[]|Error
```

Finds all matching records.

**Example:**
```ballerina
User[] users = check orm:'from(User)
    .'where({status: {equals: "ACTIVE"}})
    .findMany();
```

### create()

```ballerina
public function create(record {} data) returns Model|Error
```

Creates a new record.

**Example:**
```ballerina
User user = check orm:'from(User).create({
    email: "alice@example.com",
    name: "Alice"
});
```

### createMany()

```ballerina
public function createMany(record {}[] data) returns Model[]|Error
```

Creates multiple records.

**Example:**
```ballerina
User[] users = check orm:'from(User).createMany([
    {email: "alice@example.com", name: "Alice"},
    {email: "bob@example.com", name: "Bob"}
]);
```

### update()

```ballerina
public function update(record {} data) returns Model|Error
```

Updates a single record matching the where clause.

**Example:**
```ballerina
User user = check orm:'from(User)
    .'where({id: {equals: 1}})
    .update({name: "Alice Smith"});
```

### updateMany()

```ballerina
public function updateMany(record {} data) returns int|Error
```

Updates all records matching the where clause. Returns count of updated records.

**Example:**
```ballerina
int count = check orm:'from(User)
    .'where({status: {equals: "PENDING"}})
    .updateMany({status: "ACTIVE"});
```

### upsert()

```ballerina
public function upsert(record {|
    record {} 'where;
    record {} create;
    record {} update;
|} data) returns Model|Error
```

Creates or updates a record.

**Example:**
```ballerina
User user = check orm:'from(User).upsert({
    'where: {email: "alice@example.com"},
    create: {email: "alice@example.com", name: "Alice"},
    update: {name: "Alice Updated"}
});
```

### delete()

```ballerina
public function delete() returns Model|Error
```

Deletes a single record matching the where clause.

**Example:**
```ballerina
User deleted = check orm:'from(User)
    .'where({id: {equals: 1}})
    .delete();
```

### deleteMany()

```ballerina
public function deleteMany() returns int|Error
```

Deletes all records matching the where clause. Returns count of deleted records.

**Example:**
```ballerina
int count = check orm:'from(User)
    .'where({status: {equals: "INACTIVE"}})
    .deleteMany();
```

### count()

```ballerina
public function count() returns int|Error
```

Counts records matching the where clause.

**Example:**
```ballerina
int activeUsers = check orm:'from(User)
    .'where({status: {equals: "ACTIVE"}})
    .count();
```

### aggregate()

```ballerina
public function aggregate(record {|
    string[]? sum;
    string[]? avg;
    string[]? min;
    string[]? max;
    string[]? count;
|} operations) returns record {}|Error
```

Performs aggregation operations.

**Example:**
```ballerina
var stats = check orm:'from(Order)
    .aggregate({
        sum: ["total"],
        avg: ["total"],
        count: ["id"]
    });

io:println(`Total: ${stats.sum_total}, Avg: ${stats.avg_total}`);
```

---

## Query Builder Modifiers

### where()

```ballerina
public function 'where(record {} conditions) returns QueryBuilder
```

Adds filter conditions to the query.

**Example:**
```ballerina
User[] users = check orm:'from(User)
    .'where({
        status: {equals: "ACTIVE"},
        age: {gte: 18}
    })
    .findMany();
```

### orderBy()

```ballerina
public function orderBy(record {} ordering) returns QueryBuilder
```

Specifies sorting order. Use `orm:ASC` or `orm:DESC`.

**Example:**
```ballerina
User[] users = check orm:'from(User)
    .orderBy({createdAt: orm:DESC, email: orm:ASC})
    .findMany();
```

### skip()

```ballerina
public function skip(int count) returns QueryBuilder
```

Skips a specified number of records (for pagination).

**Example:**
```ballerina
User[] page2 = check orm:'from(User)
    .skip(10)
    .take(10)
    .findMany();
```

### take()

```ballerina
public function take(int count) returns QueryBuilder
```

Limits the number of records returned.

**Example:**
```ballerina
User[] firstTen = check orm:'from(User).take(10).findMany();
```

### select()

```ballerina
public function select(record {} fields) returns QueryBuilder
```

Selects specific fields (projection).

**Example:**
```ballerina
var users = check orm:'from(User)
    .select({id: true, email: true, name: true})
    .findMany();
```

### include()

```ballerina
public function include(record {} relations) returns QueryBuilder
```

Eagerly loads related records.

**Example:**
```ballerina
User? user = check orm:'from(User)
    .include({
        posts: true,
        profile: true
    })
    .'where({id: {equals: 1}})
    .findUnique();
```

---

## Filter Operators

### Equality

```ballerina
// Equals
{field: {equals: value}}
{field: value}  // shorthand

// Not equals
{field: {not: value}}
```

### Comparison

```ballerina
// Greater than
{age: {gt: 18}}

// Greater than or equal
{age: {gte: 18}}

// Less than
{age: {lt: 65}}

// Less than or equal
{age: {lte: 65}}
```

### Lists

```ballerina
// In list
{status: {'in: ["ACTIVE", "PENDING"]}}

// Not in list
{status: {notIn: ["DELETED", "BANNED"]}}
```

### Strings

```ballerina
// Contains substring
{email: {contains: "@example.com"}}

// Starts with
{name: {startsWith: "A"}}

// Ends with
{email: {endsWith: "@example.com"}}
```

### Null Checks

```ballerina
// Is null
{deletedAt: {isNull: true}}

// Is not null
{deletedAt: {isNull: false}}
```

### Logical Operators

```ballerina
// AND (implicit)
{
    status: {equals: "ACTIVE"},
    age: {gte: 18}
}

// OR
{
    OR: [
        {email: {endsWith: "@example.com"}},
        {email: {endsWith: "@test.com"}}
    ]
}

// NOT
{
    NOT: {
        status: {equals: "DELETED"}
    }
}

// Complex combinations
{
    AND: [
        {
            OR: [
                {type: {equals: "USER"}},
                {type: {equals: "ADMIN"}}
            ]
        },
        {status: {equals: "ACTIVE"}}
    ]
}
```

---

## Relation Operations

### Defining Relations

```ballerina
@Entity {tableName: "users"}
type User record {|
    @Id int id;
    string name;
    
    @Relation {relationType: ONE_TO_MANY}
    Post[]? posts;
    
    @Relation {relationType: ONE_TO_ONE}
    Profile? profile;
|};

@Entity {tableName: "posts"}
type Post record {|
    @Id int id;
    string title;
    int authorId;
    
    @Relation {
        relationType: MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
|};
```

### Eager Loading

```ballerina
// Load single relation
User? user = check orm:'from(User)
    .include({posts: true})
    .'where({id: {equals: 1}})
    .findUnique();

// Load multiple relations
Post? post = check orm:'from(Post)
    .include({
        author: true,
        categories: true
    })
    .findFirst();

// Nested includes
User? user = check orm:'from(User)
    .include({
        posts: {
            include: {categories: true}
        }
    })
    .findUnique();
```

### Nested Writes

```ballerina
// Create user with posts
User user = check orm:'from(User).create({
    email: "alice@example.com",
    name: "Alice",
    posts: {
        create: [
            {title: "First Post", content: "Hello"},
            {title: "Second Post", content: "World"}
        ]
    }
});
```

---

## Transactions

Use Ballerina's native `transaction` blocks:

```ballerina
transaction {
    User user = check orm:'from(User).create({
        email: "alice@example.com",
        name: "Alice"
    });
    
    Post post = check orm:'from(Post).create({
        title: "First Post",
        content: "Hello World",
        authorId: user.id
    });
    
    check commit;
}
```

### Rollback on Error

```ballerina
var result = trap transaction {
    User user = check orm:'from(User).create({...});
    
    // This will cause rollback
    _ = check orm:'from(Post).create({invalidData});
    
    check commit;
};

if result is error {
    io:println("Transaction rolled back");
}
```

---

## Raw SQL

### Raw Queries

```ballerina
stream<User, error?> users = check client.rawQuery(
    "SELECT * FROM users WHERE age > ? AND status = ?",
    18,
    "ACTIVE"
);

User[] userArray = check from User u in users select u;
```

### Raw Execution

```ballerina
int affected = check client.rawExecute(
    "UPDATE users SET last_login = NOW() WHERE id = ?",
    userId
);

io:println(`Updated ${affected} rows`);
```

---

## Types

### Provider

```ballerina
public enum Provider {
    MYSQL,
    POSTGRESQL
}
```

### RelationType

```ballerina
public enum RelationType {
    ONE_TO_ONE,
    ONE_TO_MANY,
    MANY_TO_ONE,
    MANY_TO_MANY
}
```

### Engine

```ballerina
public enum Engine {
    INNODB,
    MYISAM
}
```

### SortOrder

```ballerina
public enum SortOrder {
    ASC,
    DESC
}
```

### Error Types

```ballerina
# Base ORM error
public type Error distinct error;

# Client configuration error
public type ClientError distinct Error;

# Schema validation error
public type SchemaError distinct Error;

# Query execution error
public type QueryError distinct Error;

# Transaction error
public type TransactionError distinct Error;
```

---

## Best Practices

1. **Always use parameterized queries** — Prevents SQL injection
2. **Close clients when done** — Use `check client.close()` to release resources
3. **Use transactions for multi-step operations** — Ensures data consistency
4. **Leverage eager loading wisely** — Avoid N+1 query problems
5. **Use indexes on frequently queried fields** — Improves performance
6. **Define unique constraints** — Prevents duplicate data

---

## Next Steps

- [Migration Guide](MIGRATION_GUIDE.md) — Learn about database migrations
- [Examples](../examples/) — See complete code examples
