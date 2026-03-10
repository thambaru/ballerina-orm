import ballerina/test;
import ballerina/io;

// Integration tests for full CRUD cycle against real PostgreSQL database
// Prerequisites: Run `docker-compose -f docker-compose.test.yml up -d postgresql` before testing

Client? pgClient = ();

// Using same models as MySQL tests to ensure cross-database compatibility

@test:BeforeSuite
function setupPostgresqlIntegrationTests() returns error? {
    io:println("Setting up PostgreSQL integration tests...");
    
    // Initialize ORM client
    Client client = check new ({
        provider: POSTGRESQL,
        host: "localhost",
        port: 5433,
        user: "test_user",
        password: "test_password",
        database: "test_orm_db"
    });
    
    pgClient = client;
    
    // Clean up any existing test data
    _ = check client.rawExecute("DROP TABLE IF EXISTS post_categories CASCADE");
    _ = check client.rawExecute("DROP TABLE IF EXISTS posts CASCADE");
    _ = check client.rawExecute("DROP TABLE IF EXISTS categories CASCADE");
    _ = check client.rawExecute("DROP TABLE IF EXISTS users CASCADE");
    
    // Create tables (in production, this would be done via migrations)
    _ = check client.rawExecute(`
        CREATE TABLE users (
            id SERIAL PRIMARY KEY,
            email VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT idx_email UNIQUE (email)
        )
    `);
    
    _ = check client.rawExecute(`
        CREATE TABLE posts (
            id SERIAL PRIMARY KEY,
            title VARCHAR(500) NOT NULL,
            content TEXT NOT NULL,
            author_id INTEGER NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT fk_author FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
        )
    `);
    
    _ = check client.rawExecute(`CREATE INDEX idx_posts_author_id ON posts(author_id)`);
    
    _ = check client.rawExecute(`
        CREATE TABLE categories (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL UNIQUE,
            description TEXT
        )
    `);
    
    _ = check client.rawExecute(`
        CREATE TABLE post_categories (
            post_id INTEGER NOT NULL,
            category_id INTEGER NOT NULL,
            PRIMARY KEY (post_id, category_id),
            CONSTRAINT fk_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
            CONSTRAINT fk_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
        )
    `);
    
    io:println("PostgreSQL integration test setup complete");
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlCreateUser() returns error? {
    Client client = check getPgClient();
    
    User newUser = check 'from(User).create({
        email: "jane@example.com",
        name: "Jane Doe"
    });
    
    test:assertTrue(newUser.id > 0);
    test:assertEquals(newUser.email, "jane@example.com");
    test:assertEquals(newUser.name, "Jane Doe");
}

@test:Config {
    groups: ["integration", "postgresql"],
    dependsOn: [testPostgresqlCreateUser]
}
function testPostgresqlFindWithComplexFilters() returns error? {
    Client client = check getPgClient();
    
    // Create additional test data
    _ = check 'from(User).createMany([
        {email: "user1@test.com", name: "User One"},
        {email: "user2@test.com", name: "User Two"},
        {email: "user3@prod.com", name: "User Three"}
    ]);
    
    User[] users = check 'from(User)
        .'where({
            OR: [
                {email: {endsWith: "@test.com"}},
                {name: {contains: "Jane"}}
            ]
        })
        .orderBy({email: ASC})
        .findMany();
    
    test:assertTrue(users.length() >= 3);
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlUpsert() returns error? {
    Client client = check getPgClient();
    
    // First upsert - should create
    User user1 = check 'from(User).upsert({
        'where: {email: "upsert@example.com"},
        create: {email: "upsert@example.com", name: "Upsert User"},
        update: {name: "Updated User"}
    });
    
    test:assertEquals(user1.name, "Upsert User");
    int firstId = user1.id;
    
    // Second upsert - should update
    User user2 = check 'from(User).upsert({
        'where: {email: "upsert@example.com"},
        create: {email: "upsert@example.com", name: "Upsert User"},
        update: {name: "Updated User"}
    });
    
    test:assertEquals(user2.name, "Updated User");
    test:assertEquals(user2.id, firstId); // ID should remain the same
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlAggregation() returns error? {
    Client client = check getPgClient();
    
    // Create test data
    User author = check 'from(User).create({
        email: "agg_author@example.com",
        name: "Aggregation Author"
    });
    
    _ = check 'from(Post).createMany([
        {title: "Post 1", content: "Content 1", authorId: author.id},
        {title: "Post 2", content: "Content 2", authorId: author.id},
        {title: "Post 3", content: "Content 3", authorId: author.id}
    ]);
    
    int postCount = check 'from(Post)
        .'where({authorId: {equals: author.id}})
        .count();
    
    test:assertEquals(postCount, 3);
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlManyToManyRelation() returns error? {
    Client client = check getPgClient();
    
    // Create categories
    Category cat1 = check 'from(Category).create({
        name: "Technology",
        description: "Tech posts"
    });
    
    Category cat2 = check 'from(Category).create({
        name: "Science",
        description: "Science posts"
    });
    
    // Create author and post
    User author = check 'from(User).create({
        email: "m2m_author@example.com",
        name: "M2M Author"
    });
    
    Post post = check 'from(Post).create({
        title: "Tech and Science Post",
        content: "A post about technology and science",
        authorId: author.id
    });
    
    // Link post to categories via join table
    _ = check client.rawExecute(
        "INSERT INTO post_categories (post_id, category_id) VALUES ($1, $2), ($1, $3)",
        post.id,
        cat1.id,
        cat2.id
    );
    
    // Fetch post with categories
    Post? fetchedPost = check 'from(Post)
        .include({categories: true})
        .'where({id: {equals: post.id}})
        .findUnique();
    
    test:assertTrue(fetchedPost is Post);
    if fetchedPost is Post {
        test:assertTrue(fetchedPost.categories is Category[]);
        if fetchedPost.categories is Category[] {
            test:assertEquals(fetchedPost.categories.length(), 2);
        }
    }
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlNestedTransactionCommit() returns error? {
    Client client = check getPgClient();
    
    int initialCount = check 'from(User).count();
    
    transaction {
        _ = check 'from(User).create({
            email: "txn_nested1@example.com",
            name: "Nested Transaction 1"
        });
        
        transaction {
            _ = check 'from(User).create({
                email: "txn_nested2@example.com",
                name: "Nested Transaction 2"
            });
            
            check commit;
        }
        
        check commit;
    }
    
    int finalCount = check 'from(User).count();
    test:assertEquals(finalCount, initialCount + 2);
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlSelectProjection() returns error? {
    Client client = check getPgClient();
    
    // Create a user  
    User user = check 'from(User).create({
        email: "projection@example.com",
        name: "Projection User"
    });
    
    // Select only specific fields
    // Note: This would return a partial record type
    var result = check 'from(User)
        .select({email: true, name: true})
        .'where({id: {equals: user.id}})
        .findUnique();
    
    test:assertTrue(result is record {|string email; string name;|});
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlDeleteMany() returns error? {
    Client client = check getPgClient();
    
    // Create test users
    _ = check 'from(User).createMany([
        {email: "delete1@bulk.com", name: "Delete 1"},
        {email: "delete2@bulk.com", name: "Delete 2"},
        {email: "delete3@bulk.com", name: "Delete 3"}
    ]);
    
    // Delete all users with @bulk.com email
    int deletedCount = check 'from(User)
        .'where({email: {endsWith: "@bulk.com"}})
        .deleteMany();
    
    test:assertEquals(deletedCount, 3);
    
    // Verify deletion
    int remainingCount = check 'from(User)
        .'where({email: {endsWith: "@bulk.com"}})
        .count();
    
    test:assertEquals(remainingCount, 0);
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlRawQueryWithStreaming() returns error? {
    Client client = check getPgClient();
    
    stream<record {|int id; string email;|}, error?> resultStream = 
        check client.rawQuery("SELECT id, email FROM users LIMIT 10");
    
    int count = 0;
    check from var row in resultStream
        do {
            count += 1;
        };
    
    test:assertTrue(count >= 0);
}

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlJsonSupport() returns error? {
    Client client = check getPgClient();
    
    // Create a table with JSON column
    _ = check client.rawExecute(`
        CREATE TABLE IF NOT EXISTS settings (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL,
            preferences JSONB NOT NULL
        )
    `);
    
    // Insert JSON data
    json preferences = {
        theme: "dark",
        notifications: true,
        language: "en"
    };
    
    _ = check client.rawExecute(
        "INSERT INTO settings (user_id, preferences) VALUES ($1, $2)",
        1,
        preferences
    );
    
    // Query JSON data
    stream<record {|json preferences;|}, error?> result = 
        check client.rawQuery("SELECT preferences FROM settings WHERE user_id = $1", 1);
    
    record {|json preferences;|}[] rows = check from var row in result select row;
    
    test:assertTrue(rows.length() > 0);
    test:assertTrue(rows[0].preferences is json);
    
    // Cleanup
    _ = check client.rawExecute("DROP TABLE settings");
}

@test:AfterSuite
function cleanupPostgresqlIntegrationTests() returns error? {
    io:println("Cleaning up PostgreSQL integration tests...");
    
    Client? client = pgClient;
    if client is Client {
        _ = check client.rawExecute("DROP TABLE IF EXISTS post_categories CASCADE");
        _ = check client.rawExecute("DROP TABLE IF EXISTS posts CASCADE");
        _ = check client.rawExecute("DROP TABLE IF EXISTS categories CASCADE");
        _ = check client.rawExecute("DROP TABLE IF EXISTS users CASCADE");
        
        check client.close();
    }
    
    io:println("PostgreSQL integration test cleanup complete");
}

function getPgClient() returns Client|error {
    Client? client = pgClient;
    if client is () {
        return error("PostgreSQL client not initialized");
    }
    return client;
}
