import thambaru/bal_orm.orm;
import ballerina/io;
import ballerina/time;

public enum UserStatus {
    ACTIVE,
    INACTIVE,
    SUSPENDED
}

public enum PostStatus {
    DRAFT,
    PUBLISHED,
    ARCHIVED
}

// ----------------------------------------------------------------------------
// Flat record types for binding DB query results
// (no relation fields; timestamps are returned as strings by the DB driver)
// ----------------------------------------------------------------------------
type UserRow record {
    int id;
    string email;
    string name;
    string status;
    string? createdAt = ();
    string? updatedAt = ();
};

type PostRow record {
    int id;
    string title;
    string? excerpt;
    string content;
    string status;
    int authorId;
    string? publishedAt = ();
    string? createdAt = ();
    string? updatedAt = ();
};

type UserProfileRow record {
    int id;
    int userId;
    string? bio;
    string? website;
    string? location;
};

type CategoryRow record {
    int id;
    string name;
    string slug;
    string? description;
    string? createdAt = ();
};

type CommentRow record {
    int id;
    string content;
    int postId;
    int authorId;
    string? createdAt = ();
    string? updatedAt = ();
};

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
    UserStatus status = ACTIVE; // ACTIVE, INACTIVE, SUSPENDED
    
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
    PostStatus status = DRAFT; // DRAFT, PUBLISHED, ARCHIVED
    
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
    // Initialize database client (MySQL)
    orm:Client db = check new ({
        provider: orm:MYSQL,
        host: "localhost",
        port: 3306,
        user: "root",
        password: "password",
        database: "blog_app"
    });

    // Uncomment to use PostgreSQL instead:
    // orm:Client dbs = check new ({
    //     provider: orm:MYSQL,
    //     host: "localhost",
    //     port: 3306,
    //     user: "root",
    //     password: "password",
    //     database: "blog_app"
    // });
    
    io:println(sep("=", 60));
    io:println("Blog Application Example - Ballerina ORM");
    io:println(sep("=", 60));

    // Reset database so the script can be run repeatedly
    check resetDatabase(db);

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

// Truncate all tables and reset identity sequences so the script is idempotent.
function resetDatabase(orm:Client db) returns error? {
    _ = check db.rawExecute(
        "TRUNCATE TABLE post_categories, comments, posts, user_profiles, categories, users RESTART IDENTITY CASCADE"
    );
}

// Example 1: Create users
function example1_createUsers(orm:Client db) returns error? {
    io:println("\n📝 Example 1: Creating Users");
    io:println(sep("-", 40));
    
    // Create single user
    UserRow thambaru = check (check db.'from(User).create({
        email: "hi@thambaru.com",
        name: "Thambaru",
        status: ACTIVE
    })).cloneWithType();
    
    io:println(`Created user: ${thambaru.name} (ID: ${thambaru.id})`);
    
    // Create multiple users
    UserRow[] users = check (check db.'from(User).createMany([
        {email: "kasun@example.com", name: "Kasun Perera", status: ACTIVE},
        {email: "nadeesha@example.com", name: "Nadeesha Fernando", status: ACTIVE},
        {email: "chathura@example.com", name: "Chathura Silva", status: INACTIVE}
    ])).cloneWithType();
    
    io:println(`Created ${users.length()} more users`);
    
    // Create user profile
    UserProfileRow _ = check (check db.'from(UserProfile).create({
        userId: thambaru.id,
        bio: "Software engineer passionate about distributed systems",
        website: "https://thambaru.com",
        location: "Sri Lanka"
    })).cloneWithType();
    
    io:println(`Created profile for ${thambaru.name}`);
}

// Example 2: Create posts with relations
function example2_createPosts(orm:Client db) returns error? {
    io:println("\n📝 Example 2: Creating Posts");
    io:println(sep("-", 40));
    
    // Get a user to be the author
    record {}? thambaruRow = check db.'from(User)
        .'where({email: {'equals: "hi@thambaru.com"}})
        .findUnique();
    
    if thambaruRow is () {
        return error("User not found");
    }
    UserRow thambaru = check thambaruRow.cloneWithType();
    
    // Create posts
    PostRow post1 = check (check db.'from(Post).create({
        title: "Getting Started with Ballerina ORM",
        excerpt: "Learn how to build type-safe database applications",
        content: "Ballerina ORM provides a Prisma-like experience for Ballerina developers...",
        status: PUBLISHED,
        authorId: thambaru.id,
        publishedAt: time:utcNow()
    })).cloneWithType();
    
    PostRow post2 = check (check db.'from(Post).create({
        title: "Advanced Query Patterns",
        excerpt: "Master complex queries and relations",
        content: "In this post, we'll explore advanced patterns for querying databases...",
        status: DRAFT,
        authorId: thambaru.id
    })).cloneWithType();
    
    io:println(`Created ${[post1, post2].length()} posts for ${thambaru.name}`);
    _ = post1;
    _ = post2;
}

// Example 3: Query with filters
function example3_queryWithFilters(orm:Client db) returns error? {
    io:println("\n🔍 Example 3: Querying with Filters");
    io:println(sep("-", 40));
    
    // Simple equality filter
    UserRow[] activeUsers = check (check db.'from(User)
        .'where({status: {'equals: ACTIVE}})
        .orderBy({email: orm:ASC})
        .findMany()).cloneWithType();
    
    io:println(`Found ${activeUsers.length()} active users`);
    
    // String matching
    UserRow[] exampleUsers = check (check db.'from(User)
        .'where({email: {contains: "@example.com"}})
        .findMany()).cloneWithType();
    
    io:println(`Found ${exampleUsers.length()} users with @example.com emails`);
    
    // Logical operators
    UserRow[] filteredUsers = check (check db.'from(User)
        .'where({
            OR: [
                {status: {'equals: ACTIVE}},
                {email: {startsWith: "thambaru"}}
            ]
        })
        .findMany()).cloneWithType();
    
    io:println(`Found ${filteredUsers.length()} users matching complex filter`);
    
    // Published posts only
    PostRow[] publishedPosts = check (check db.'from(Post)
        .'where({
            status: {'equals: PUBLISHED},
            publishedAt: {isNull: false}
        })
        .orderBy({publishedAt: orm:DESC})
        .findMany()).cloneWithType();
    
    io:println(`Found ${publishedPosts.length()} published posts`);
}

// Example 4: Loading relations via separate queries
function example4_eagerLoadRelations(orm:Client db) returns error? {
    io:println("\n🔗 Example 4: Loading Relations");
    io:println(sep("-", 40));
    
    // Load user
    record {}? thambaruRow = check db.'from(User)
        .'where({email: {'equals: "hi@thambaru.com"}})
        .findUnique();
    
    if thambaruRow is record {} {
        UserRow thambaru = check thambaruRow.cloneWithType();
        io:println(`User: ${thambaru.name}`);
        
        // Load profile separately
        record {}? profileRow = check db.'from(UserProfile)
            .'where({userId: {'equals: thambaru.id}})
            .findFirst();
        if profileRow is record {} {
            UserProfileRow userProfile = check profileRow.cloneWithType();
            io:println(`  Profile bio: ${userProfile.bio ?: "No bio"}`);
        }
        
        // Load posts separately
        PostRow[] posts = check (check db.'from(Post)
            .'where({authorId: {'equals: thambaru.id}})
            .findMany()).cloneWithType();
        io:println(`  Posts: ${posts.length()}`);
        foreach PostRow p in posts {
            io:println(`    - ${p.title} (${p.status}`);
        }
    }
    
    // Load first post then its comments separately
    record {}? postRow = check db.'from(Post).findFirst();
    
    if postRow is record {} {
        PostRow post = check postRow.cloneWithType();
        io:println("");
        io:println(`Post: ${post.title}`);
        io:println(`  Author ID: ${post.authorId}`);
        
        CommentRow[] comments = check (check db.'from(Comment)
            .'where({postId: {'equals: post.id}})
            .findMany()).cloneWithType();
        io:println(`  Comments: ${comments.length()}`);
    }
}

// Example 5: Pagination
function example5_pagination(orm:Client db) returns error? {
    io:println("\n📄 Example 5: Pagination");
    io:println(sep("-", 40));
    
    int pageSize = 2;
    int _ = 1; // currentPage placeholder
    
    // Get total count
    int totalUsers = check db.'from(User).count();
    int totalPages = (totalUsers + pageSize - 1) / pageSize;
    
    io:println(`Total users: ${totalUsers}, Pages: ${totalPages}`);
    
    // Get page 1
    UserRow[] page1 = check (check db.'from(User)
        .orderBy({id: orm:ASC})
        .skip(0)
        .take(pageSize)
        .findMany()).cloneWithType();
    
    io:println("");
    io:println("Page 1:");
    foreach UserRow user in page1 {
        io:println(`  - ${user.name} (${user.email})`);
    }
    
    // Get page 2
    UserRow[] page2 = check (check db.'from(User)
        .orderBy({id: orm:ASC})
        .skip(pageSize)
        .take(pageSize)
        .findMany()).cloneWithType();
    
    io:println("");
    io:println("Page 2:");
    foreach UserRow user in page2 {
        io:println(`  - ${user.name} (${user.email})`);
    }
}

// Example 6: Aggregations
function example6_aggregations(orm:Client db) returns error? {
    io:println("\n📊 Example 6: Aggregations");
    io:println(sep("-", 40));
    
    // Count users by status
    int activeCount = check db.'from(User)
        .'where({status: {'equals: ACTIVE}})
        .count();
    
    int inactiveCount = check db.'from(User)
        .'where({status: {'equals: INACTIVE}})
        .count();
    
    io:println(`Active users: ${activeCount}`);
    io:println(`Inactive users: ${inactiveCount}`);
    
    // Count posts by author
    record {}? thambaruRow = check db.'from(User)
        .'where({email: {'equals: "hi@thambaru.com"}})
        .findUnique();
    
    if thambaruRow is record {} {
        UserRow thambaru = check thambaruRow.cloneWithType();
        int postCount = check db.'from(Post)
            .'where({authorId: {'equals: thambaru.id}})
            .count();
        
        io:println(`${thambaru.name} has ${postCount} posts`);
    }
}

// Example 7: Transactions
function example7_transactions(orm:Client db) returns error? {
    io:println("\n💳 Example 7: Transactions");
    io:println(sep("-", 40));
    
    // Successful transaction
    transaction {
        UserRow newUser = check (check db.'from(User).create({
            email: "transaction@example.com",
            name: "Transaction User",
            status: ACTIVE
        })).cloneWithType();
        
        UserProfileRow _ = check (check db.'from(UserProfile).create({
            userId: newUser.id,
            bio: "Created within a transaction"
        })).cloneWithType();
        
        io:println(`Created user and profile in transaction: ${newUser.name}`);
        
        check commit;
    }
    
    // Transaction with rollback
    transaction {
        UserRow _ = check (check db.'from(User).create({
            email: "rollback@example.com",
            name: "Rollback User",
            status: ACTIVE
        })).cloneWithType();
        
        // Simulate error to trigger rollback (check propagates error, causing rollback)
        check error("Simulated error for rollback");
        
        check commit;
    } on fail {
        io:println("Transaction rolled back successfully");
    }
    
    // Verify rollback
    record {}? rolledBackRow = check db.'from(User)
        .'where({email: {'equals: "rollback@example.com"}})
        .findUnique();
    
    if rolledBackRow is () {
        io:println("Rollback user was not created (as expected)");
    }
}

// Example 8: Many-to-many relations
function example8_manyToManyRelations(orm:Client db) returns error? {
    io:println("\n🔀 Example 8: Many-to-Many Relations");
    io:println(sep("-", 40));
    
    // Create categories
    CategoryRow tech = check (check db.'from(Category).create({
        name: "Technology",
        slug: "technology",
        description: "Tech-related posts"
    })).cloneWithType();
    
    CategoryRow tutorial = check (check db.'from(Category).create({
        name: "Tutorial",
        slug: "tutorial",
        description: "Step-by-step guides"
    })).cloneWithType();
    
    io:println(`Created categories: ${tech.name}, ${tutorial.name}`);
    
    // Get a post
    record {}? postRow = check db.'from(Post)
        .'where({status: {'equals: PUBLISHED}})
        .findFirst();
    
    if postRow is record {} {
        PostRow post = check postRow.cloneWithType();
        
        // Link post to categories (using raw SQL for join table)
        _ = check db.rawExecute(
            "INSERT INTO post_categories (post_id, category_id) VALUES ($1, $2), ($3, $4)",
            [post.id, tech.id, post.id, tutorial.id]
        );
        
        io:println(`Linked post "${post.title}" to categories`);
        
        // Query categories for this post via raw SQL
        stream<record {}, error?> catStream = check db.rawQuery(
            "SELECT c.id, c.name FROM categories c JOIN post_categories pc ON c.id = pc.category_id WHERE pc.post_id = $1",
            [post.id]
        );
        record {}[] catRows = check from var r in catStream select r;
        io:println(`Post categories (${catRows.length()}):`);
        foreach var catRow in catRows {
            io:println(`  - ${catRow["name"].toString()}`);
        }
    }
}

// Example 9: Complex queries
function example9_complexQueries(orm:Client db) returns error? {
    io:println("\n🔍 Example 9: Complex Queries");
    io:println(sep("-", 40));
    
    // Complex filter with nested conditions
    PostRow[] posts = check (check db.'from(Post)
        .'where({
            AND: [
                {
                    OR: [
                        {status: {'equals: PUBLISHED}},
                        {status: {'equals: DRAFT}}
                    ]
                },
                {
                    title: {contains: "Ballerina"}
                }
            ]
        })
        .orderBy({createdAt: orm:DESC})
        .take(10)
        .findMany()).cloneWithType();
    
    io:println(`Found ${posts.length()} posts matching complex criteria`);
    
    // Select specific fields
    record {}[] userEmails = check (check db.'from(User)
        .'select({id: true, email: true, name: true})
        .'where({status: {'equals: ACTIVE}})
        .findMany()).cloneWithType();
    
    io:println(`Retrieved ${userEmails.length()} user emails (projected)`);
    
    // Update multiple records
    int updatedCount = check db.'from(Post)
        .'where({status: {'equals: DRAFT}})
        .updateMany({status: ARCHIVED});
    
    io:println(`Archived ${updatedCount} draft posts`);
}

// Example 10: Raw SQL
function example10_rawSql(orm:Client db) returns error? {
    io:println("\n🛠️ Example 10: Raw SQL");
    io:println(sep("-", 40));
    
    // Raw query — use generic record stream since column names may differ by driver
    stream<record {}, error?> resultStream = 
        check db.rawQuery(
            "SELECT u.name, COUNT(p.id) as post_count" +
            " FROM users u" +
            " LEFT JOIN posts p ON u.id = p.author_id" +
            " GROUP BY u.id, u.name" +
            " HAVING COUNT(p.id) > 0" +
            " ORDER BY COUNT(p.id) DESC"
        );
    
    record {}[] results = check from var row in resultStream select row;
    
    io:println("Authors by post count:");
    foreach var author in results {
        io:println(`  ${author["name"].toString()}: ${author["post_count"].toString()} posts`);
    }
    
    // Raw execute for custom operations
    _ = check db.rawExecute(
        "UPDATE users" +
        " SET updated_at = NOW()" +
        " WHERE id IN (SELECT DISTINCT author_id FROM posts WHERE status = 'PUBLISHED')"
    );
    
    io:println("Updated timestamps for authors with published posts");
}

// ============================================================================
// HELPERS
// ============================================================================

function sep(string s, int n) returns string {
    string result = "";
    foreach int _ in 0 ..< n {
        result = result + s;
    }
    return result;
}
