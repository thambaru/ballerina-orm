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
