import thambaru/bal_orm.orm;
import ballerina/io;
import ballerina/time;

// ============================================================================
// SCHEMA DEFINITION
// ============================================================================

@orm:Entity {tableName: "users"}
@orm:Index {columns: ["email"], unique: true}
@orm:Index {columns: ["status", "createdAt"]}
public type User record {|
    @orm:Id @orm:AutoIncrement
    int id;
    
    @orm:Column {length: 255, nullable: false}
    string email;
    
    @orm:Column {length: 100}
    string name;
    
    @orm:Column {length: 20}
    string status = "ACTIVE"; // ACTIVE, INACTIVE, SUSPENDED
    
    @orm:CreatedAt
    time:Utc createdAt;
    
    @orm:UpdatedAt
    time:Utc updatedAt;
    
    // Relations
    @orm:Relation {'type: orm:ONE_TO_MANY}
    Post[]? posts;
    
    @orm:Relation {'type: orm:ONE_TO_ONE}
    UserProfile? profile;
|};

@orm:Entity {tableName: "user_profiles"}
public type UserProfile record {|
    @orm:Id @orm:AutoIncrement
    int id;
    
    @orm:Column {nullable: false}
    int userId; // Foreign key to users.id
    
    @orm:Column {'type: "TEXT"}
    string? bio;
    
    @orm:Column {length: 255}
    string? website;
    
    @orm:Column {length: 100}
    string? location;
    
    @orm:Relation {
        'type: orm:ONE_TO_ONE,
        references: ["id"],
        foreignKey: ["userId"]
    }
    User? user;
|};

@orm:Entity {tableName: "posts"}
@orm:Index {columns: ["authorId"]}
@orm:Index {columns: ["status", "publishedAt"]}
public type Post record {|
    @orm:Id @orm:AutoIncrement
    int id;
    
    @orm:Column {length: 500, nullable: false}
    string title;
    
    @orm:Column {length: 1000}
    string? excerpt;
    
    @orm:Column {'type: "TEXT", nullable: false}
    string content;
    
    @orm:Column {length: 20}
    string status = "DRAFT"; // DRAFT, PUBLISHED, ARCHIVED
    
    @orm:Column {nullable: false}
    int authorId; // Foreign key to users.id
    
    time:Utc? publishedAt;
    
    @orm:CreatedAt
    time:Utc createdAt;
    
    @orm:UpdatedAt
    time:Utc updatedAt;
    
    // Relations
    @orm:Relation {
        'type: orm:MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
    
    @orm:Relation {
        'type: orm:MANY_TO_MANY,
        joinTable: "post_categories"
    }
    Category[]? categories;
    
    @orm:Relation {'type: orm:ONE_TO_MANY}
    Comment[]? comments;
|};

@orm:Entity {tableName: "categories"}
@orm:Index {columns: ["slug"], unique: true}
public type Category record {|
    @orm:Id @orm:AutoIncrement
    int id;
    
    @orm:Column {length: 100, unique: true, nullable: false}
    string name;
    
    @orm:Column {length: 150, unique: true, nullable: false}
    string slug;
    
    @orm:Column {'type: "TEXT"}
    string? description;
    
    @orm:CreatedAt
    time:Utc createdAt;
|};

@orm:Entity {tableName: "comments"}
@orm:Index {columns: ["postId"]}
@orm:Index {columns: ["authorId"]}
public type Comment record {|
    @orm:Id @orm:AutoIncrement
    int id;
    
    @orm:Column {'type: "TEXT", nullable: false}
    string content;
    
    @orm:Column {nullable: false}
    int postId; // Foreign key to posts.id
    
    @orm:Column {nullable: false}
    int authorId; // Foreign key to users.id
    
    @orm:CreatedAt
    time:Utc createdAt;
    
    @orm:UpdatedAt
    time:Utc updatedAt;
    
    // Relations
    @orm:Relation {
        'type: orm:MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["postId"]
    }
    Post? post;
    
    @orm:Relation {
        'type: orm:MANY_TO_ONE,
        references: ["id"],
        foreignKey: ["authorId"]
    }
    User? author;
|};

// ============================================================================
// APPLICATION
// ============================================================================

public function main() returns error? {
    // Initialize database client
    orm:Client db = check new ({
        provider: orm:MYSQL,
        host: "localhost",
        port: 3306,
        user: "root",
        password: "password",
        database: "blog_app",
        connectionPool: {
            maxPoolSize: 10
        }
    });
    
    io:println("=".repeat(60));
    io:println("Blog Application Example - Ballerina ORM");
    io:println("=".repeat(60));
    
    // Example 1: Create users
    check example1_createUsers(db);
    
    // Example 2: Create posts with relations
    check example2_createPosts(db);
    
    // Example 3: Query with filters
    check example3_queryWithFilters(db);
    
    // Example 4: Eager loading relations
    check example4_eagerLoadRelations(db);
    
    // Example 5: Pagination
    check example5_pagination(db);
    
    // Example 6: Aggregations
    check example6_aggregations(db);
    
    // Example 7: Transactions
    check example7_transactions(db);
    
    // Example 8: Many-to-many relations
    check example8_manyToManyRelations(db);
    
    // Example 9: Complex queries
    check example9_complexQueries(db);
    
    // Example 10: Raw SQL
    check example10_rawSql(db);
    
    // Cleanup
    check db.close();
    io:println("\n✨ All examples completed successfully!");
}

// Example 1: Create users
function example1_createUsers(orm:Client db) returns error? {
    io:println("\n📝 Example 1: Creating Users");
    io:println("-".repeat(40));
    
    // Create single user
    User alice = check db.'from(User).create({
        email: "alice@example.com",
        name: "Alice Smith",
        status: "ACTIVE"
    });
    
    io:println(`Created user: ${alice.name} (ID: ${alice.id})`);
    
    // Create multiple users
    User[] users = check db.'from(User).createMany([
        {email: "bob@example.com", name: "Bob Johnson", status: "ACTIVE"},
        {email: "charlie@example.com", name: "Charlie Brown", status: "ACTIVE"},
        {email: "diana@example.com", name: "Diana Prince", status: "INACTIVE"}
    ]);
    
    io:println(`Created ${users.length()} more users`);
    
    // Create user profile
    UserProfile profile = check db.'from(UserProfile).create({
        userId: alice.id,
        bio: "Software engineer passionate about distributed systems",
        website: "https://alice.dev",
        location: "San Francisco, CA"
    });
    
    io:println(`Created profile for ${alice.name}`);
}

// Example 2: Create posts with relations
function example2_createPosts(orm:Client db) returns error? {
    io:println("\n📝 Example 2: Creating Posts");
    io:println("-".repeat(40));
    
    // Get a user to be the author
    User? alice = check db.'from(User)
        .'where({email: {equals: "alice@example.com"}})
        .findUnique();
    
    if alice is () {
        return error("User not found");
    }
    
    // Create posts
    Post post1 = check db.'from(Post).create({
        title: "Getting Started with Ballerina ORM",
        excerpt: "Learn how to build type-safe database applications",
        content: "Ballerina ORM provides a Prisma-like experience for Ballerina developers...",
        status: "PUBLISHED",
        authorId: alice.id,
        publishedAt: time:utcNow()
    });
    
    Post post2 = check db.'from(Post).create({
        title: "Advanced Query Patterns",
        excerpt: "Master complex queries and relations",
        content: "In this post, we'll explore advanced patterns for querying databases...",
        status: "DRAFT",
        authorId: alice.id
    });
    
    io:println(`Created ${[post1, post2].length()} posts for ${alice.name}`);
}

// Example 3: Query with filters
function example3_queryWithFilters(orm:Client db) returns error? {
    io:println("\n🔍 Example 3: Querying with Filters");
    io:println("-".repeat(40));
    
    // Simple equality filter
    User[] activeUsers = check db.'from(User)
        .'where({status: {equals: "ACTIVE"}})
        .orderBy({email: orm:ASC})
        .findMany();
    
    io:println(`Found ${activeUsers.length()} active users`);
    
    // String matching
    User[] exampleUsers = check db.'from(User)
        .'where({email: {contains: "@example.com"}})
        .findMany();
    
    io:println(`Found ${exampleUsers.length()} users with @example.com emails`);
    
    // Logical operators
    User[] filteredUsers = check db.'from(User)
        .'where({
            OR: [
                {status: {equals: "ACTIVE"}},
                {email: {startsWith: "alice"}}
            ]
        })
        .findMany();
    
    io:println(`Found ${filteredUsers.length()} users matching complex filter`);
    
    // Published posts only
    Post[] publishedPosts = check db.'from(Post)
        .'where({
            status: {equals: "PUBLISHED"},
            publishedAt: {isNull: false}
        })
        .orderBy({publishedAt: orm:DESC})
        .findMany();
    
    io:println(`Found ${publishedPosts.length()} published posts`);
}

// Example 4: Eager loading relations
function example4_eagerLoadRelations(orm:Client db) returns error? {
    io:println("\n🔗 Example 4: Eager Loading Relations");
    io:println("-".repeat(40));
    
    // Load user with posts
    User? alice = check db.'from(User)
        .include({posts: true, profile: true})
        .'where({email: {equals: "alice@example.com"}})
        .findUnique();
    
    if alice is User {
        io:println(`User: ${alice.name}`);
        
        if alice.profile is UserProfile {
            io:println(`  Profile: ${alice.profile.bio ?: "No bio"}`);
        }
        
        if alice.posts is Post[] {
            io:println(`  Posts: ${alice.posts.length()}`);
            foreach Post post in alice.posts {
                io:println(`    - ${post.title} (${post.status})`);
            }
        }
    }
    
    // Load post with author and comments
    Post? post = check db.'from(Post)
        .include({
            author: true,
            comments: true
        })
        .findFirst();
    
    if post is Post {
        io:println(`\nPost: ${post.title}`);
        if post.author is User {
            io:println(`  Author: ${post.author.name}`);
        }
        if post.comments is Comment[] {
            io:println(`  Comments: ${post.comments.length()}`);
        }
    }
}

// Example 5: Pagination
function example5_pagination(orm:Client db) returns error? {
    io:println("\n📄 Example 5: Pagination");
    io:println("-".repeat(40));
    
    int pageSize = 2;
    int currentPage = 1;
    
    // Get total count
    int totalUsers = check db.'from(User).count();
    int totalPages = (totalUsers + pageSize - 1) / pageSize;
    
    io:println(`Total users: ${totalUsers}, Pages: ${totalPages}`);
    
    // Get page 1
    User[] page1 = check db.'from(User)
        .orderBy({id: orm:ASC})
        .skip(0)
        .take(pageSize)
        .findMany();
    
    io:println(`\nPage 1:`);
    foreach User user in page1 {
        io:println(`  - ${user.name} (${user.email})`);
    }
    
    // Get page 2
    User[] page2 = check db.'from(User)
        .orderBy({id: orm:ASC})
        .skip(pageSize)
        .take(pageSize)
        .findMany();
    
    io:println(`\nPage 2:`);
    foreach User user in page2 {
        io:println(`  - ${user.name} (${user.email})`);
    }
}

// Example 6: Aggregations
function example6_aggregations(orm:Client db) returns error? {
    io:println("\n📊 Example 6: Aggregations");
    io:println("-".repeat(40));
    
    // Count users by status
    int activeCount = check db.'from(User)
        .'where({status: {equals: "ACTIVE"}})
        .count();
    
    int inactiveCount = check db.'from(User)
        .'where({status: {equals: "INACTIVE"}})
        .count();
    
    io:println(`Active users: ${activeCount}`);
    io:println(`Inactive users: ${inactiveCount}`);
    
    // Count posts by author
    User? alice = check db.'from(User)
        .'where({email: {equals: "alice@example.com"}})
        .findUnique();
    
    if alice is User {
        int postCount = check db.'from(Post)
            .'where({authorId: {equals: alice.id}})
            .count();
        
        io:println(`${alice.name} has ${postCount} posts`);
    }
}

// Example 7: Transactions
function example7_transactions(orm:Client db) returns error? {
    io:println("\n💳 Example 7: Transactions");
    io:println("-".repeat(40));
    
    // Successful transaction
    transaction {
        User newUser = check db.'from(User).create({
            email: "transaction@example.com",
            name: "Transaction User",
            status: "ACTIVE"
        });
        
        UserProfile newProfile = check db.'from(UserProfile).create({
            userId: newUser.id,
            bio: "Created within a transaction"
        });
        
        io:println(`Created user and profile in transaction: ${newUser.name}`);
        
        check commit;
    }
    
    // Transaction with rollback
    var result = trap transaction {
        User tempUser = check db.'from(User).create({
            email: "rollback@example.com",
            name: "Rollback User",
            status: "ACTIVE"
        });
        
        // Simulate error
        error simulatedError = error("Simulated error for rollback");
        fail simulatedError;
        
        check commit;
    };
    
    if result is error {
        io:println("Transaction rolled back successfully");
    }
    
    // Verify rollback
    User? rolledBackUser = check db.'from(User)
        .'where({email: {equals: "rollback@example.com"}})
        .findUnique();
    
    if rolledBackUser is () {
        io:println("Rollback user was not created (as expected)");
    }
}

// Example 8: Many-to-many relations
function example8_manyToManyRelations(orm:Client db) returns error? {
    io:println("\n🔀 Example 8: Many-to-Many Relations");
    io:println("-".repeat(40));
    
    // Create categories
    Category tech = check db.'from(Category).create({
        name: "Technology",
        slug: "technology",
        description: "Tech-related posts"
    });
    
    Category tutorial = check db.'from(Category).create({
        name: "Tutorial",
        slug: "tutorial",
        description: "Step-by-step guides"
    });
    
    io:println(`Created categories: ${tech.name}, ${tutorial.name}`);
    
    // Get a post
    Post? post = check db.'from(Post)
        .'where({status: {equals: "PUBLISHED"}})
        .findFirst();
    
    if post is Post {
        // Link post to categories (using raw SQL for join table)
        _ = check db.rawExecute(
            "INSERT INTO post_categories (post_id, category_id) VALUES (?, ?), (?, ?)",
            [post.id, tech.id, post.id, tutorial.id]
        );
        
        io:println(`Linked post "${post.title}" to categories`);
        
        // Load post with categories
        Post? postWithCategories = check db.'from(Post)
            .include({categories: true})
            .'where({id: {equals: post.id}})
            .findUnique();
        
        if postWithCategories is Post && postWithCategories.categories is Category[] {
            io:println(`Post categories (${postWithCategories.categories.length()}):`);
            foreach Category cat in postWithCategories.categories {
                io:println(`  - ${cat.name}`);
            }
        }
    }
}

// Example 9: Complex queries
function example9_complexQueries(orm:Client db) returns error? {
    io:println("\n🔍 Example 9: Complex Queries");
    io:println("-".repeat(40));
    
    // Complex filter with nested conditions
    Post[] posts = check db.'from(Post)
        .'where({
            AND: [
                {
                    OR: [
                        {status: {equals: "PUBLISHED"}},
                        {status: {equals: "DRAFT"}}
                    ]
                },
                {
                    title: {contains: "Ballerina"}
                }
            ]
        })
        .orderBy({createdAt: orm:DESC})
        .take(10)
        .findMany();
    
    io:println(`Found ${posts.length()} posts matching complex criteria`);
    
    // Select specific fields
    var userEmails = check db.'from(User)
        .select({id: true, email: true, name: true})
        .'where({status: {equals: "ACTIVE"}})
        .findMany();
    
    io:println(`Retrieved ${userEmails.length()} user emails (projected)`);
    
    // Update multiple records
    int updatedCount = check db.'from(Post)
        .'where({status: {equals: "DRAFT"}})
        .updateMany({status: "ARCHIVED"});
    
    io:println(`Archived ${updatedCount} draft posts`);
}

// Example 10: Raw SQL
function example10_rawSql(orm:Client db) returns error? {
    io:println("\n🛠️ Example 10: Raw SQL");
    io:println("-".repeat(40));
    
    // Raw query
    stream<record {|string name; int post_count;|}, error?> resultStream = 
        check db.rawQuery(`
            SELECT u.name, COUNT(p.id) as post_count
            FROM users u
            LEFT JOIN posts p ON u.id = p.author_id
            GROUP BY u.id, u.name
            HAVING post_count > 0
            ORDER BY post_count DESC
        `);
    
    record {|string name; int post_count;|}[] results = 
        check from var row in resultStream select row;
    
    io:println("Authors by post count:");
    foreach var author in results {
        io:println(`  ${author.name}: ${author.post_count} posts`);
    }
    
    // Raw execute for custom operations
    _ = check db.rawExecute(`
        UPDATE users 
        SET updated_at = NOW() 
        WHERE id IN (SELECT DISTINCT author_id FROM posts WHERE status = 'PUBLISHED')
    `);
    
    io:println("Updated timestamps for authors with published posts");
}
