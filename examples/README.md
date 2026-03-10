# Ballerina ORM Examples

This directory contains comprehensive examples demonstrating the features and capabilities of Ballerina ORM.

## Examples Overview

### 1. `complete_blog_example.bal`

A complete blog application demonstrating:
- **Schema Definition**: User, Post, Category, Comment models with relations
- **CRUD Operations**: Create, read, update, delete for all entities
- **Relations**: ONE_TO_ONE, ONE_TO_MANY, MANY_TO_MANY
- **Query Patterns**: Filters, pagination, sorting, aggregations
- **Eager Loading**: Including related records efficiently
- **Transactions**: Multi-step operations with rollback
- **Raw SQL**: Complex custom queries

**Run the example:**
```bash
cd examples
bal run complete_blog_example.bal
```

### 2. `bal_orm_cli.bal`

CLI tool demonstrating:
- Migration commands integration
- Schema introspection
- Database pushing/pulling
- Interactive command-line interface

**Run the example:**
```bash
bal run bal_orm_cli.bal migrate dev --name init
bal run bal_orm_cli.bal db pull
bal run bal_orm_cli.bal migrate status
```

### 3. `migration_demo.bal`

Migration workflow demonstration:
- Initializing migrations
- Generating migration files
- Applying/rolling back migrations
- Schema diffing
- Multiple database support

**Run the example:**
```bash
bal run migration_demo.bal
```

## Prerequisites

### Database Setup

Before running the examples, you need a running MySQL or PostgreSQL database.

#### Using Docker (Recommended)

```bash
# Start MySQL
docker run -d \
  --name ballerina-orm-mysql \
  -e MYSQL_ROOT_PASSWORD=password \
  -e MYSQL_DATABASE=blog_app \
  -p 3306:3306 \
  mysql:8.0

# Or start PostgreSQL
docker run -d \
  --name ballerina-orm-postgres \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=blog_app \
  -p 5432:5432 \
  postgres:15-alpine
```

#### Using Docker Compose

Use the test setup:
```bash
cd ..
docker-compose -f docker-compose.test.yml up -d
```

### Environment Configuration

Create a `.env` file or set environment variables:

```bash
export DB_PROVIDER=mysql
export DB_HOST=localhost
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=password
export DB_DATABASE=blog_app
```

Or use a connection URL:

```bash
export DB_URL="mysql://root:password@localhost:3306/blog_app"
```

## Running the Examples

### Example 1: Complete Blog Application

This example creates a full blog with users, posts, categories, and comments.

```bash
cd examples
bal run complete_blog_example.bal
```

**What it demonstrates:**

1. **Schema Definition** (Lines 12-178)
   - Entity annotations (`@Entity`, `@Id`, `@AutoIncrement`)
   - Column configuration (`@Column`)
   - Relations (`@Relation`)
   - Indexes (`@Index`)
   - Timestamps (`@CreatedAt`, `@UpdatedAt`)

2. **Basic CRUD** (Lines 206-238)
   - Creating single records
   - Creating multiple records
   - Finding records with filters
   - Updating records
   - Deleting records

3. **Query Patterns** (Lines 260-290)
   - Equality filters
   - String matching (contains, startsWith, endsWith)
   - Comparison operators (gte, lte)
   - Logical operators (AND, OR, NOT)
   - Sorting and ordering

4. **Relations** (Lines 292-340)
   - Eager loading with `.include()`
   - ONE_TO_MANY relations (User → Posts)
   - MANY_TO_ONE relations (Post → User)
   - ONE_TO_ONE relations (User → Profile)
   - MANY_TO_MANY relations (Post ↔ Category)

5. **Advanced Features** (Lines 342-400)
   - Pagination with `.skip()` and `.take()`
   - Aggregations (count, sum, avg)
   - Transactions with rollback
   - Raw SQL for complex queries

**Expected Output:**

```
============================================================
Blog Application Example - Ballerina ORM
============================================================

📝 Example 1: Creating Users
----------------------------------------
Created user: Alice Smith (ID: 1)
Created 3 more users
Created profile for Alice Smith

📝 Example 2: Creating Posts
----------------------------------------
Created 2 posts for Alice Smith

🔍 Example 3: Querying with Filters
----------------------------------------
Found 3 active users
Found 4 users with @example.com emails
Found 4 users matching complex filter
Found 1 published posts

🔗 Example 4: Eager Loading Relations
----------------------------------------
User: Alice Smith
  Profile: Software engineer passionate about distributed systems
  Posts: 2
    - Getting Started with Ballerina ORM (PUBLISHED)
    - Advanced Query Patterns (DRAFT)
...
```

### Example 2: CLI Tool

Demonstrates the CLI commands for migration management.

```bash
bal run bal_orm_cli.bal migrate dev --name create_users
```

**Available Commands:**

```bash
# Initialize migrations
bal run bal_orm_cli.bal init

# Create migration
bal run bal_orm_cli.bal migrate dev --name <name>

# Check migration status
bal run bal_orm_cli.bal migrate status

# Deploy migrations (production)
bal run bal_orm_cli.bal migrate deploy

# Reset database (dev only)
bal run bal_orm_cli.bal migrate reset

# Push schema changes directly
bal run bal_orm_cli.bal db push

# Pull schema from existing database
bal run bal_orm_cli.bal db pull --output models.bal
```

### Example 3: Migration Demo

Shows the complete migration workflow.

```bash
bal run migration_demo.bal
```

This example:
1. Connects to the database
2. Introspects the current schema
3. Compares with desired schema (from annotations)
4. Generates SQL migrations
5. Applies migrations
6. Verifies the changes

## Common Use Cases

### Use Case 1: Simple CRUD Application

```ballerina
import thambaru/bal_orm.orm;

@orm:Entity {tableName: "products"}
type Product record {|
    @orm:Id @orm:AutoIncrement
    int id;
    string name;
    decimal price;
|};

public function main() returns error? {
    orm:Client db = check new ({...});
    
    // Create
    Product product = check orm:'from(Product).create({
        name: "Laptop",
        price: 999.99
    });
    
    // Read
    Product[] products = check orm:'from(Product)
        .'where({price: {lte: 1000}})
        .findMany();
    
    // Update
    Product updated = check orm:'from(Product)
        .'where({id: {equals: 1}})
        .update({price: 899.99});
    
    // Delete
    _ = check orm:'from(Product)
        .'where({id: {equals: 1}})
        .delete();
}
```

### Use Case 2: Blog with Relations

```ballerina
@orm:Entity {tableName: "posts"}
type Post record {|
    @orm:Id int id;
    string title;
    int authorId;
    
    @orm:Relation {
        relationType: orm:MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
|};

// Get post with author
Post? post = check orm:'from(Post)
    .include({author: true})
    .'where({id: {equals: 1}})
    .findUnique();
```

### Use Case 3: Pagination

```ballerina
// Get page 2 with 10 items per page
User[] page = check orm:'from(User)
    .orderBy({createdAt: orm:DESC})
    .skip(10)
    .take(10)
    .findMany();
    
int total = check orm:'from(User).count();
io:println(`Showing 10 of ${total} users`);
```

### Use Case 4: Complex Filtering

```ballerina
User[] users = check orm:'from(User)
    .'where({
        AND: [
            {status: {equals: "ACTIVE"}},
            {
                OR: [
                    {email: {endsWith: "@company.com"}},
                    {role: {equals: "ADMIN"}}
                ]
            }
        ]
    })
    .findMany();
```

### Use Case 5: Aggregations

```ballerina
var stats = check orm:'from(Order)
    .'where({status: {equals: "COMPLETED"}})
    .aggregate({
        sum: ["total"],
        avg: ["total"],
        count: ["id"]
    });

io:println(`Revenue: $${stats.sum_total}, Avg: $${stats.avg_total}`);
```

## Troubleshooting

### Connection Issues

```
Error: Cannot connect to database
```

**Solution:**
1. Verify database is running: `docker ps`
2. Check connection parameters in code
3. Test connection using database client

### Migration Conflicts

```
Error: Migration already applied
```

**Solution:**
```bash
bal run bal_orm_cli.bal migrate status
bal run bal_orm_cli.bal migrate resolve --applied <migration_name>
```

### Schema Out of Sync

```
Error: Table does not exist
```

**Solution:**
```bash
bal run bal_orm_cli.bal migrate dev --name sync_schema
```

## Next Steps

- Read the [API Reference](../docs/API_REFERENCE.md) for complete API documentation
- Check the [Migration Guide](../docs/MIGRATION_GUIDE.md) for migration workflows
- Review the [README](../README.md) for getting started guide

## Contributing

Found an issue with the examples? Have a suggestion for a new example? Open an issue or submit a PR!
