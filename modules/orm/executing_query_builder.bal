import ballerina/sql;

# Fluent query builder that is pre-bound to a live ORM client.
# Terminal methods execute immediately — no separate query-runner step required.
#
# Obtain one via `db.'from(ModelType)` — the primary Prisma-like API entry point.
#
# Example:
# ```ballerina
# User[] users = check db.'from(User)
#     .'where({email: {contains: "@example.com"}})
#     .orderBy({id: orm:DESC})
#     .take(10)
#     .findMany();
# ```
public class ExecutingQueryBuilder {
    private final Client dbClient;
    private QueryPlan plan;

    public function init(Client dbClient, string modelName) {
        self.dbClient = dbClient;
        self.plan = {model: modelName};
    }

    # Override table name for this query.
    public function 'table(string tableName) returns ExecutingQueryBuilder {
        self.plan.tableName = tableName;
        return self;
    }

    # Add a where filter.
    public function 'where(WhereInput whereInput) returns ExecutingQueryBuilder {
        self.plan.'where = whereInput;
        return self;
    }

    # Add an order-by clause.
    public function orderBy(OrderByInput orderByInput) returns ExecutingQueryBuilder {
        self.plan.orderBy.push(orderByInput);
        return self;
    }

    # Set result offset.
    public function skip(int value) returns ExecutingQueryBuilder {
        self.plan.skip = value;
        return self;
    }

    # Set result size limit.
    public function take(int value) returns ExecutingQueryBuilder {
        self.plan.take = value;
        return self;
    }

    # Add select projection.
    public function 'select(SelectInput selectInput) returns ExecutingQueryBuilder {
        self.plan.'select = selectInput;
        return self;
    }

    # Add relation include payload.
    public function include(IncludeInput includeInput) returns ExecutingQueryBuilder {
        self.plan.include = includeInput;
        return self;
    }

    # Execute the query and return all matching rows as a generic record array.
    # Use `cloneWithType()` on the result to obtain a typed array:
    # ```ballerina
    # User[] users = check (check db.'from(User).findMany()).cloneWithType();
    # ```
    public function findMany() returns record {}[]|error {
        self.plan.operation = FIND_MANY;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is error {
            return rows;
        }
        return rows;
    }

    # Execute the query and return the first matching row, or nil if none found.
    # Use `cloneWithType()` on the result to obtain a typed value.
    public function findFirst() returns record {}?|error {
        self.plan.operation = FIND_FIRST;
        self.plan.take = 1;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is error {
            return rows;
        }
        return rows.length() > 0 ? rows[0] : ();
    }

    # Execute the query and return the unique matching row, or nil if none found.
    # Use `cloneWithType()` on the result to obtain a typed value.
    public function findUnique() returns record {}?|error {
        self.plan.operation = FIND_UNIQUE;
        self.plan.take = 1;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is error {
            return rows;
        }
        return rows.length() > 0 ? rows[0] : ();
    }

    # Execute a count query and return the row count.
    public function count() returns int|error {
        self.plan.operation = COUNT;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is error {
            return rows;
        }
        if rows.length() > 0 {
            anydata countVal = rows[0]["count"];
            if countVal is int {
                return countVal;
            }
        }
        return 0;
    }

    # Execute a create query and return the created row as a generic record.
    #
    # Inserts the row then fetches the full record using the auto-generated primary key.
    # Assumes the primary key column is named `id`.
    # Use `cloneWithType()` on the result to obtain a typed value:
    # ```ballerina
    # User alice = check (check db.'from(User).create({...})).cloneWithType();
    # ```
    public function create(map<anydata> data) returns record {}|error {
        self.plan.operation = CREATE;
        self.plan.data = data;
        sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(self.plan);
        if execResult is error {
            return execResult;
        }
        string|int? lastId = execResult.lastInsertId;
        string|int resolvedId;
        if lastId is () {
            // PostgreSQL may not populate lastInsertId via JDBC getGeneratedKeys; fall back to lastval()
            int|error lastValResult = postgresqlLastVal(self.dbClient);
            if lastValResult is error {
                return error("CREATE_FETCH_FAILED", message = "No lastInsertId returned and lastval() failed: " + lastValResult.message());
            }
            resolvedId = lastValResult;
        } else {
            resolvedId = lastId;
        }
        string tableName = self.plan.tableName ?: toDefaultTableName(self.plan.model);
        record {}?|error row = fetchInsertedRow(self.dbClient, tableName, resolvedId);
        if row is error {
            return row;
        }
        if row is () {
            return error("CREATE_FETCH_FAILED", message = "Created row could not be retrieved.");
        }
        return row;
    }

    # Execute a createMany query and return all created rows as a generic record array.
    #
    # Inserts each row individually and fetches results via auto-generated primary keys.
    # Assumes the primary key column is named `id`.
    public function createMany(map<anydata>[] dataList) returns record {}[]|error {
        record {}[] results = [];
        string tableName = self.plan.tableName ?: toDefaultTableName(self.plan.model);
        string modelName = self.plan.model;
        foreach map<anydata> data in dataList {
            QueryPlan insertPlan = {
                model: modelName,
                tableName: self.plan.tableName,
                operation: CREATE,
                data: data,
                orderBy: []
            };
            sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(insertPlan);
            if execResult is error {
                return execResult;
            }
            string|int? lastId = execResult.lastInsertId;
            string|int resolvedId;
            if lastId is () {
                int|error lastValResult = postgresqlLastVal(self.dbClient);
                if lastValResult is error {
                    return error("CREATEMANY_FETCH_FAILED", message = "No lastInsertId and lastval() failed: " + lastValResult.message());
                }
                resolvedId = lastValResult;
            } else {
                resolvedId = lastId;
            }
            record {}?|error insertedRow = fetchInsertedRow(self.dbClient, tableName, resolvedId);
            if insertedRow is error {
                return insertedRow;
            }
            if insertedRow is () {
                return error("CREATEMANY_FETCH_FAILED", message = "Created row could not be retrieved.");
            }
            results.push(insertedRow);
        }
        return results;
    }

    # Execute an update query and return the updated row as a generic record.
    #
    # Updates the matching row (limited to one) then fetches back the updated record.
    public function update(map<anydata> data) returns record {}|error {
        self.plan.operation = UPDATE;
        self.plan.data = data;
        sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(self.plan);
        if execResult is error {
            return execResult;
        }
        QueryPlan fetchPlan = {
            model: self.plan.model,
            tableName: self.plan.tableName,
            operation: FIND_FIRST,
            'where: self.plan.'where,
            take: 1,
            orderBy: []
        };
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, fetchPlan);
        if rows is error {
            return rows;
        }
        if rows.length() == 0 {
            return error("UPDATE_ROW_NOT_FOUND", message = "Updated row could not be retrieved.");
        }
        return rows[0];
    }

    # Execute an updateMany query and return the number of affected rows.
    public function updateMany(map<anydata> data) returns int|error {
        self.plan.operation = UPDATE_MANY;
        self.plan.data = data;
        sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(self.plan);
        if execResult is error {
            return execResult;
        }
        return execResult.affectedRowCount ?: 0;
    }

    # Execute an upsert query (insert if not exists, otherwise update).
    public function upsert(map<anydata> createData, map<anydata> updateData) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = UPSERT;
        self.plan.upsert = {
            create: createData,
            update: updateData
        };
        return self.dbClient.execute(self.plan);
    }

    # Execute a delete query, returning the deleted row as a generic record.
    #
    # Fetches the matching record before deletion, deletes it, then returns the fetched record.
    public function delete() returns record {}|error {
        QueryPlan fetchPlan = {
            model: self.plan.model,
            tableName: self.plan.tableName,
            operation: FIND_FIRST,
            'where: self.plan.'where,
            take: 1,
            orderBy: []
        };
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, fetchPlan);
        if rows is error {
            return rows;
        }
        if rows.length() == 0 {
            return error("DELETE_ROW_NOT_FOUND", message = "Row to delete could not be found.");
        }
        record {} deletedRow = rows[0];
        self.plan.operation = DELETE;
        sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(self.plan);
        if execResult is error {
            return execResult;
        }
        return deletedRow;
    }

    # Execute a deleteMany query and return the number of affected rows.
    public function deleteMany() returns int|error {
        self.plan.operation = DELETE_MANY;
        sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(self.plan);
        if execResult is error {
            return execResult;
        }
        return execResult.affectedRowCount ?: 0;
    }
}

# Shared helper: run a read QueryPlan and collect all rows.
function executeReadPlan(Client dbClient, QueryPlan plan)
        returns record {}[]|SchemaError|ClientError|sql:Error {
    stream<record {}, sql:Error?>|SchemaError|ClientError|sql:Error queryResult = dbClient.query(plan);
    if queryResult is stream<record {}, sql:Error?> {
        record {}[]|error rows = from var r in queryResult select r;
        if rows is sql:Error {
            return rows;
        }
        if rows is error {
            return error sql:ApplicationError(rows.message());
        }
        record {}[] camelRows = (<record {}[]>rows).map(convertRowToCamel);
        return camelRows;
    }
    return queryResult;
}

# Fetch a single row by its auto-generated primary key (assumed column name: `id`).
# Used internally after INSERT to return the full inserted record.
function fetchInsertedRow(Client dbClient, string tableName, string|int rowId) returns record {}?|error {
    anydata[] params = [rowId];
    string sql;
    if dbClient.provider == POSTGRESQL {
        sql = "SELECT * FROM \"" + tableName + "\" WHERE \"id\" = $1 LIMIT 1";
    } else {
        sql = "SELECT * FROM `" + tableName + "` WHERE `id` = ? LIMIT 1";
    }
    stream<record {}, sql:Error?>|ClientError|sql:Error queryResult = dbClient.rawQuery(sql, params);
    if queryResult is error {
        return queryResult;
    }
    record {}[]|error rows = from var r in queryResult select r;
    if rows is error {
        return rows;
    }
    if rows.length() == 0 {
        return ();
    }
    return convertRowToCamel((<record {}[]>rows)[0]);
}

# For PostgreSQL: query the last inserted id using lastval().
function postgresqlLastVal(Client dbClient) returns int|error {
    stream<record {}, sql:Error?>|ClientError|sql:Error result = dbClient.rawQuery("SELECT lastval() AS id");
    if result is error {
        return result;
    }
    record {}[]|error rows = from var r in result select r;
    if rows is error {
        return rows;
    }
    if rows.length() > 0 {
        anydata idVal = rows[0]["id"];
        if idVal is int {
            return idVal;
        }
    }
    return error("LASTVAL_FAILED", message = "Could not retrieve last inserted id from PostgreSQL.");
}

# Convert a database result row's snake_case keys to camelCase.
# e.g. `created_at` → `createdAt`, `author_id` → `authorId`
function convertRowToCamel(record {} row) returns record {} {
    map<anydata> result = {};
    foreach var [key, value] in row.entries() {
        result[snakeToCamel(key)] = value;
    }
    return result;
}

# Convert a snake_case string to camelCase.
# e.g. `created_at` → `createdAt`, `user_id` → `userId`
function snakeToCamel(string s) returns string {
    string result = "";
    boolean nextUpper = false;
    int i = 0;
    while i < s.length() {
        string ch = s.substring(i, i + 1);
        if ch == "_" {
            nextUpper = true;
        } else if nextUpper {
            result += ch.toUpperAscii();
            nextUpper = false;
        } else {
            result += ch;
        }
        i += 1;
    }
    return result;
}
