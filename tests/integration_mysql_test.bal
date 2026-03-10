import ballerina/test;
import ballerina/io;

// Integration tests for full CRUD cycle against real MySQL database
// Prerequisites: Run `docker-compose -f docker-compose.test.yml up -d mysql` before testing

Client? mysqlClient = ();

// Define test models matching Phase 1 schema definition
@Entity {tableName: "users"}
@Index {columns: ["email"], unique: true}
type User record {|
    @Id @AutoIncrement
    int id;
    @Column {length: 255, nullable: false}
    string email;
    string name;
    @CreatedAt
    string createdAt;
    @Relation {relationType: ONE_TO_MANY}
    Post[]? posts;
|};

@Entity {tableName: "posts"}
@Index {columns: ["authorId"]}
type Post record {|
    @Id @AutoIncrement
    int id;
    string title;
    string content;
    @Column {nullable: false}
    int authorId;
    @Relation {relationType: MANY_TO_ONE, references: ["id"], foreignKey: ["authorId"]}
    User? author;
    @Relation {relationType: MANY_TO_MANY, joinTable: "post_categories"}
    Category[]? categories;
    @CreatedAt
    string createdAt;
|};

@Entity {tableName: "categories"}
type Category record {|
    @Id @AutoIncrement
    int id;
    @Column {length: 100, unique: true}
    string name;
    string? description;
|};

@test:BeforeSuite
function setupMysqlIntegrationTests() returns error? {
    io:println("Setting up MySQL integration tests...");
    
    // Initialize ORM client
    Client client = check new ({
        provider: MYSQL,
        host: "localhost",
        port: 3307,
        user: "test_user",
        password: "test_password",
        database: "test_orm_db"
    });
    
    mysqlClient = client;
    
    // Clean up any existing test data
    _ = check client.rawExecute("DROP TABLE IF EXISTS post_categories");
    _ = check client.rawExecute("DROP TABLE IF EXISTS posts");
    _ = check client.rawExecute("DROP TABLE IF EXISTS categories");
    _ = check client.rawExecute("DROP TABLE IF EXISTS users");
    
    // Create tables (in production, this would be done via migrations)
    _ = check client.rawExecute(`
        CREATE TABLE users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE INDEX idx_email (email)
        )
    `);
    
    _ = check client.rawExecute(`
        CREATE TABLE posts (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(500) NOT NULL,
            content TEXT NOT NULL,
            author_id INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_author_id (author_id),
            FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
        )
    `);
    
    _ = check client.rawExecute(`
        CREATE TABLE categories (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL UNIQUE,
            description TEXT
        )
    `);
    
    _ = check client.rawExecute(`
        CREATE TABLE post_categories (
            post_id INT NOT NULL,
            category_id INT NOT NULL,
            PRIMARY KEY (post_id, category_id),
            FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
            FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
        )
    `);
    
    io:println("MySQL integration test setup complete");
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlCreateUser() returns error? {
    Client client = check getClient();
    
    User newUser = check 'from(User).create({
        email: "john@example.com",
        name: "John Doe"
    });
    
    test:assertTrue(newUser.id > 0);
    test:assertEquals(newUser.email, "john@example.com");
    test:assertEquals(newUser.name, "John Doe");
    test:assertTrue(newUser.createdAt.length() > 0);
}

@test:Config {
    groups: ["integration", "mysql"],
    dependsOn: [testMysqlCreateUser]
}
function testMysqlFindUniqueUser() returns error? {
    Client client = check getClient();
    
    User? user = check 'from(User)
        .'where({email: {equals: "john@example.com"}})
        .findUnique();
    
    test:assertTrue(user is User);
    if user is User {
        test:assertEquals(user.email, "john@example.com");
        test:assertEquals(user.name, "John Doe");
    }
}

@test:Config {
    groups: ["integration", "mysql"],
    dependsOn: [testMysqlCreateUser]
}
function testMysqlUpdateUser() returns error? {
    Client client = check getClient();
    
    User updatedUser = check 'from(User)
        .'where({email: {equals: "john@example.com"}})
        .update({name: "John Smith"});
    
    test:assertEquals(updatedUser.name, "John Smith");
    test:assertEquals(updatedUser.email, "john@example.com");
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlCreateMultipleUsers() returns error? {
    Client client = check getClient();
    
    User[] users = check 'from(User).createMany([
        {email: "alice@example.com", name: "Alice"},
        {email: "bob@example.com", name: "Bob"},
        {email: "charlie@example.com", name: "Charlie"}
    ]);
    
    test:assertEquals(users.length(), 3);
    test:assertEquals(users[0].name, "Alice");
    test:assertEquals(users[1].name, "Bob");
    test:assertEquals(users[2].name, "Charlie");
}

@test:Config {
    groups: ["integration", "mysql"],
    dependsOn: [testMysqlCreateMultipleUsers]
}
function testMysqlFindManyWithFilters() returns error? {
    Client client = check getClient();
    
    User[] users = check 'from(User)
        .'where({
            email: {contains: "@example.com"},
            name: {startsWith: "A"}
        })
        .orderBy({name: ASC})
        .findMany();
    
    test:assertTrue(users.length() >= 1);
    test:assertEquals(users[0].name, "Alice");
}

@test:Config {
    groups: ["integration", "mysql"],
    dependsOn: [testMysqlCreateMultipleUsers]
}
function testMysqlPaginationSkipTake() returns error? {
    Client client = check getClient();
    
    User[] page1 = check 'from(User)
        .orderBy({id: ASC})
        .skip(0)
        .take(2)
        .findMany();
    
    User[] page2 = check 'from(User)
        .orderBy({id: ASC})
        .skip(2)
        .take(2)
        .findMany();
    
    test:assertEquals(page1.length(), 2);
    test:assertTrue(page2.length() >= 1);
    test:assertNotEquals(page1[0].id, page2[0].id);
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlCreatePostWithRelation() returns error? {
    Client client = check getClient();
    
    // Create a user first
    User author = check 'from(User).create({
        email: "author@example.com",
        name: "Author"
    });
    
    // Create a post linked to the user
    Post post = check 'from(Post).create({
        title: "My First Post",
        content: "This is the content of my first post.",
        authorId: author.id
    });
    
    test:assertTrue(post.id > 0);
    test:assertEquals(post.title, "My First Post");
    test:assertEquals(post.authorId, author.id);
}

@test:Config {
    groups: ["integration", "mysql"],
    dependsOn: [testMysqlCreatePostWithRelation]
}
function testMysqlEagerLoadRelation() returns error? {
    Client client = check getClient();
    
    Post? post = check 'from(Post)
        .include({author: true})
        .'where({title: {equals: "My First Post"}})
        .findFirst();
    
    test:assertTrue(post is Post);
    if post is Post {
        test:assertEquals(post.title, "My First Post");
        test:assertTrue(post.author is User);
        if post.author is User {
            test:assertEquals(post.author.email, "author@example.com");
        }
    }
}

@test:Config {
    groups: ["integration", "mysql"],
    dependsOn: [testMysqlCreatePostWithRelation]
}
function testMysqlOneToManyRelation() returns error? {
    Client client = check getClient();
    
    User? user = check 'from(User)
        .include({posts: true})
        .'where({email: {equals: "author@example.com"}})
        .findUnique();
    
    test:assertTrue(user is User);
    if user is User {
        test:assertTrue(user.posts is Post[]);
        if user.posts is Post[] {
            test:assertTrue(user.posts.length() >= 1);
            test:assertEquals(user.posts[0].title, "My First Post");
        }
    }
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlCountQuery() returns error? {
    Client client = check getClient();
    
    int count = check 'from(User)
        .'where({email: {contains: "@example.com"}})
        .count();
    
    test:assertTrue(count > 0);
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlDeleteOperation() returns error? {
    Client client = check getClient();
    
    // Create a temporary user
    User tempUser = check 'from(User).create({
        email: "temp@example.com",
        name: "Temp User"
    });
    
    // Delete the user
    User deletedUser = check 'from(User)
        .'where({id: {equals: tempUser.id}})
        .delete();
    
    test:assertEquals(deletedUser.id, tempUser.id);
    
    // Verify deletion
    User? found = check 'from(User)
        .'where({id: {equals: tempUser.id}})
        .findUnique();
    
    test:assertTrue(found is ());
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlTransaction() returns error? {
    Client client = check getClient();
    
    transaction {
        User user1 = check 'from(User).create({
            email: "txn1@example.com",
            name: "Transaction User 1"
        });
        
        User user2 = check 'from(User).create({
            email: "txn2@example.com",
            name: "Transaction User 2"
        });
        
        check commit;
    }
    
    // Verify both users were created
    User? user1 = check 'from(User)
        .'where({email: {equals: "txn1@example.com"}})
        .findUnique();
    
    User? user2 = check 'from(User)
        .'where({email: {equals: "txn2@example.com"}})
        .findUnique();
    
    test:assertTrue(user1 is User);
    test:assertTrue(user2 is User);
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlTransactionRollback() returns error? {
    Client client = check getClient();
    
    var result = trap transaction {
        User user = check 'from(User).create({
            email: "rollback@example.com",
            name: "Rollback User"
        });
        
        // Force an error to trigger rollback
        error err = error("Forced rollback");
        fail err;
    };
    
    // Verify user was NOT created (rollback succeeded)
    User? found = check 'from(User)
        .'where({email: {equals: "rollback@example.com"}})
        .findUnique();
    
    test:assertTrue(found is ());
}

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlRawQuery() returns error? {
    Client client = check getClient();
    
    stream<User, error?> userStream = check client.rawQuery(
        "SELECT * FROM users WHERE email LIKE ?",
        "%@example.com"
    );
    
    User[] users = check from User user in userStream select user;
    
    test:assertTrue(users.length() > 0);
}

@test:AfterSuite
function cleanupMysqlIntegrationTests() returns error? {
    io:println("Cleaning up MySQL integration tests...");
    
    Client? client = mysqlClient;
    if client is Client {
        _ = check client.rawExecute("DROP TABLE IF EXISTS post_categories");
        _ = check client.rawExecute("DROP TABLE IF EXISTS posts");
        _ = check client.rawExecute("DROP TABLE IF EXISTS categories");
        _ = check client.rawExecute("DROP TABLE IF EXISTS users");
        
        check client.close();
    }
    
    io:println("MySQL integration test cleanup complete");
}

function getClient() returns Client|error {
    Client? client = mysqlClient;
    if client is () {
        return error("MySQL client not initialized");
    }
    return client;
}
