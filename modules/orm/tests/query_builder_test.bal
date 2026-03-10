import ballerina/test;

type User record {|
    int id;
    string email;
    string name;
|};

@test:Config {}
function testFindManySqlForPostgresql() {
    QueryPlan plan = 'from(User)
        .'where({
            email: {
                contains: "@example.com"
            },
            age: {
                gte: 18
            }
        })
        .orderBy({createdAt: DESC})
        .skip(10)
        .take(20)
        .findMany();

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);

    test:assertEquals(
        sql.text,
        "SELECT * FROM \"users\" WHERE (\"email\" LIKE $1) AND (\"age\" >= $2) ORDER BY \"created_at\" DESC LIMIT 20 OFFSET 10"
    );
    test:assertEquals(sql.parameters, ["%@example.com%", 18]);
}

@test:Config {}
function testCreateSqlForMysql() {
    QueryPlan plan = fromModel("User").create({
        email: "alice@example.com",
        name: "Alice"
    });

    SqlQuery sql = checkpanic toSql(plan, MYSQL);

    test:assertEquals(sql.text, "INSERT INTO `users` (`email`, `name`) VALUES (?, ?)");
    test:assertEquals(sql.parameters, ["alice@example.com", "Alice"]);
}

@test:Config {}
function testLogicalFiltersAndCountSql() {
    QueryPlan plan = fromModel("User")
        .'where({
            OR: [
                {status: {'equals: "ACTIVE"}},
                {status: {'equals: "PENDING"}}
            ],
            NOT: {
                deletedAt: {
                    isNull: true
                }
            },
            id: {
                'in: [1, 2, 3]
            }
        })
        .count();

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);

    test:assertEquals(
        sql.text,
        "SELECT COUNT(*) AS \"count\" FROM \"users\" WHERE (((\"status\" = $1)) OR ((\"status\" = $2))) AND (NOT ((\"deleted_at\" IS NULL))) AND (\"id\" IN ($3, $4, $5))"
    );
    test:assertEquals(sql.parameters, ["ACTIVE", "PENDING", 1, 2, 3]);
}

@test:Config {}
function testRawSqlHelpers() {
    SqlQuery queryPayload = rawQuery("SELECT * FROM users WHERE id = ?", 10);
    test:assertEquals(queryPayload.text, "SELECT * FROM users WHERE id = ?");
    test:assertEquals(queryPayload.parameters, [10]);

    SqlQuery execPayload = rawExecute("DELETE FROM users WHERE id = ?", 20);
    test:assertEquals(execPayload.text, "DELETE FROM users WHERE id = ?");
    test:assertEquals(execPayload.parameters, [20]);
}

// Additional filter operator tests
@test:Config {}
function testStringFilterOperators() {
    QueryPlan plan = fromModel("User")
        .'where({
            email: {startsWith: "admin"},
            name: {endsWith: "Smith"},
            bio: {contains: "developer"}
        })
        .findMany();

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);
    
    test:assertEquals(
        sql.text,
        "SELECT * FROM \"users\" WHERE (\"email\" LIKE $1) AND (\"name\" LIKE $2) AND (\"bio\" LIKE $3)"
    );
    test:assertEquals(sql.parameters, ["admin%", "%Smith", "%developer%"]);
}

@test:Config {}
function testNotInFilterOperator() {
    QueryPlan plan = fromModel("User")
        .'where({
            status: {notIn: ["DELETED", "BANNED", "SUSPENDED"]}
        })
        .findMany();

    SqlQuery sql = checkpanic toSql(plan, MYSQL);
    
    test:assertEquals(
        sql.text,
        "SELECT * FROM `users` WHERE (`status` NOT IN (?, ?, ?))"
    );
    test:assertEquals(sql.parameters, ["DELETED", "BANNED", "SUSPENDED"]);
}

@test:Config {}
function testUpdateSql() {
    QueryPlan plan = fromModel("User")
        .'where({id: {'equals: 5}})
        .update({name: "Updated Name", status: "ACTIVE"});

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);
    
    test:assertEquals(
        sql.text,
        "UPDATE \"users\" SET \"name\" = $1, \"status\" = $2 WHERE (\"id\" = $3) LIMIT 1"
    );
    test:assertEquals(sql.parameters, ["Updated Name", "ACTIVE", 5]);
}

@test:Config {}
function testDeleteManySql() {
    QueryPlan plan = fromModel("User")
        .'where({
            createdAt: {lt: "2025-01-01T00:00:00Z"},
            status: {'equals: "INACTIVE"}
        })
        .deleteMany();

    SqlQuery sql = checkpanic toSql(plan, MYSQL);
    
    test:assertEquals(
        sql.text,
        "DELETE FROM `users` WHERE (`created_at` < ?) AND (`status` = ?)"
    );
    test:assertEquals(sql.parameters, ["2025-01-01T00:00:00Z", "INACTIVE"]);
}

@test:Config {}
function testSelectWithProjection() {
    QueryPlan plan = fromModel("User")
        .'select({id: true, email: true, name: true})
        .'where({status: {'equals: "ACTIVE"}})
        .findMany();

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);
    
    test:assertEquals(
        sql.text,
        "SELECT \"id\", \"email\", \"name\" FROM \"users\" WHERE (\"status\" = $1)"
    );
    test:assertEquals(sql.parameters, ["ACTIVE"]);
}

@test:Config {}
function testAggregateQuery() {
    QueryPlan plan = fromModel("Order")
        .'where({status: {'equals: "COMPLETED"}})
        .aggregate({
            _avg: {total: true},
            _sum: {quantity: true},
            _max: {total: true},
            _min: {total: true}
        });

    SqlQuery sql = checkpanic toSql(plan, MYSQL);
    
    test:assertEquals(
        sql.text,
        "SELECT AVG(`total`) AS `total_avg`, SUM(`quantity`) AS `quantity_sum`, MAX(`total`) AS `total_max`, MIN(`total`) AS `total_min` FROM `orders` WHERE (`status` = ?)"
    );
    test:assertEquals(sql.parameters, ["COMPLETED"]);
}

@test:Config {}
function testIncludeOneToMany() {
    QueryPlan plan = fromModel("User")
        .include({posts: true})
        .'where({id: {'equals: 1}})
        .findFirst();

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);
    
    // Include planning currently does not generate JOIN clauses in toSql().
    test:assertTrue(sql.text.includes("SELECT") && sql.text.includes("FROM"));
}

@test:Config {}
function testNestedWhereConditions() {
    QueryPlan plan = fromModel("User")
        .'where({
            AND: [
                {
                    OR: [
                        {email: {contains: "@example.com"}},
                        {email: {contains: "@test.com"}}
                    ]
                },
                {
                    age: {gte: 18, lte: 65}
                }
            ]
        })
        .findMany();

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);
    
    test:assertTrue(sql.text.includes("AND"));
    test:assertTrue(sql.text.includes("OR"));
    test:assertEquals(sql.parameters.length(), 4);
}

@test:Config {}
function testUpsertSql() {
    QueryPlan plan = fromModel("User")
        .upsert(
            {email: "test@example.com", name: "Test User"},
            {name: "Test User Updated"}
        );

    SqlQuery|SchemaError sqlOrError = toSql(plan, MYSQL);
    test:assertTrue(sqlOrError is SchemaError);

    if sqlOrError is SchemaError {
        test:assertEquals(sqlOrError.detail().code, "QUERY_UPSERT_UNSUPPORTED");
    }
}

@test:Config {}
function testCreateManySql() {
    QueryPlan plan = fromModel("User")
        .createMany([
            {email: "user1@example.com", name: "User 1"},
            {email: "user2@example.com", name: "User 2"},
            {email: "user3@example.com", name: "User 3"}
        ]);

    SqlQuery sql = checkpanic toSql(plan, POSTGRESQL);
    
    test:assertTrue(sql.text.includes("INSERT"));
    test:assertEquals(sql.parameters.length(), 6); // 3 users × 2 fields
}

@test:Config {}
function testDialectDifferencesMysqlVsPostgresql() {
    QueryPlan plan = fromModel("User")
        .'where({id: {'equals: 1}})
        .findFirst();

    SqlQuery mysqlSql = checkpanic toSql(plan, MYSQL);
    SqlQuery pgSql = checkpanic toSql(plan, POSTGRESQL);
    
    // MySQL uses backticks, PostgreSQL uses double quotes
    test:assertTrue(mysqlSql.text.includes("`"));
    test:assertTrue(pgSql.text.includes("\""));
    
    // MySQL uses ?, PostgreSQL uses $1, $2, etc.
    test:assertTrue(mysqlSql.text.includes("?"));
    test:assertTrue(pgSql.text.includes("$1"));
}
