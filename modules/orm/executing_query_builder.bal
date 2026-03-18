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
    #
    # + tableName - Custom table name to use instead of the model-derived default.
    # + return - Updated builder with the custom table name applied.
    public function 'table(string tableName) returns ExecutingQueryBuilder {
        self.plan.tableName = tableName;
        return self;
    }

    # Add a where filter.
    #
    # + whereInput - Filter predicate map.
    # + return - Updated builder with the where clause applied.
    public function 'where(WhereInput whereInput) returns ExecutingQueryBuilder {
        self.plan.'where = whereInput;
        return self;
    }

    # Add an order-by clause.
    #
    # + orderByInput - Field-to-direction map specifying sort order.
    # + return - Updated builder with the order-by clause appended.
    public function orderBy(OrderByInput orderByInput) returns ExecutingQueryBuilder {
        self.plan.orderBy.push(orderByInput);
        return self;
    }

    # Set result offset.
    #
    # + value - Number of rows to skip.
    # + return - Updated builder with the skip value set.
    public function skip(int value) returns ExecutingQueryBuilder {
        self.plan.skip = value;
        return self;
    }

    # Set result size limit.
    #
    # + value - Maximum number of rows to return.
    # + return - Updated builder with the take value set.
    public function take(int value) returns ExecutingQueryBuilder {
        self.plan.take = value;
        return self;
    }

    # Add select projection.
    #
    # + selectInput - Field projection map.
    # + return - Updated builder with the select projection applied.
    public function 'select(SelectInput selectInput) returns ExecutingQueryBuilder {
        self.plan.'select = selectInput;
        return self;
    }

    # Add relation include payload.
    #
    # + includeInput - Relation include map.
    # + return - Updated builder with the include clause applied.
    public function include(IncludeInput includeInput) returns ExecutingQueryBuilder {
        self.plan.include = includeInput;
        return self;
    }

    # Execute the query and return all matching rows as a generic record array.
    # Cast the result to your model type using a type descriptor.
    #
    # + return - Array of generic record rows, or an error.
    public function findMany() returns record {}[]|error {
        self.plan.operation = FIND_MANY;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is error {
            return rows;
        }
        return rows;
    }

    # Execute the query and return the first matching row, or nil if none found.
    # Cast the result to your model type using a type descriptor.
    #
    # + return - The first matching generic record, nil if no match, or an error.
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
    # Cast the result to your model type using a type descriptor.
    #
    # + return - The unique matching generic record, nil if no match, or an error.
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
    #
    # + return - Number of rows matching the current filter, or an error.
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
    # Cast the result to your model type using a type descriptor.
    #
    # + data - Field values to insert.
    # + return - The newly inserted generic record, or an error.
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

    # Execute a createMany query using a single batch INSERT and return all created rows.
    #
    # Assumes the primary key column is named `id` and is auto-incremented.
    #
    # + dataList - List of field value maps to insert.
    # + return - Array of newly inserted generic records, or an error.
    public function createMany(map<anydata>[] dataList) returns record {}[]|error {
        if dataList.length() == 0 {
            return [];
        }

        self.plan.operation = CREATE_MANY;
        self.plan.dataList = dataList;
        sql:ExecutionResult|SchemaError|ClientError|sql:Error execResult = self.dbClient.execute(self.plan);
        if execResult is error {
            return execResult;
        }

        string tableName = self.plan.tableName ?: toDefaultTableName(self.plan.model);
        string|int? lastId = execResult.lastInsertId;
        int rowCount = dataList.length();

        if lastId is int {
            // For auto-increment, fetch all inserted rows by ID range
            int firstId = lastId - rowCount + 1;
            return fetchInsertedRows(self.dbClient, tableName, firstId, rowCount);
        }

        if lastId is () && self.dbClient.provider == POSTGRESQL {
            // PostgreSQL: lastval() gives the last id; compute the range
            int|error lastValResult = postgresqlLastVal(self.dbClient);
            if lastValResult is error {
                return error("CREATEMANY_FETCH_FAILED", message = "No lastInsertId and lastval() failed: " + lastValResult.message());
            }
            int firstId = lastValResult - rowCount + 1;
            return fetchInsertedRows(self.dbClient, tableName, firstId, rowCount);
        }

        // Fallback: re-fetch individually if we cannot determine the ID range
        record {}[] results = [];
        string modelName = self.plan.model;
        foreach map<anydata> data in dataList {
            QueryPlan insertFetchPlan = {
                model: modelName,
                tableName: self.plan.tableName,
                operation: FIND_FIRST,
                'where: data,
                take: 1,
                orderBy: []
            };
            record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, insertFetchPlan);
            if rows is error {
                return rows;
            }
            if rows.length() > 0 {
                results.push(rows[0]);
            }
        }
        return results;
    }

    # Execute an update query and return the updated row as a generic record.
    #
    # Updates the matching row (limited to one) then fetches back the updated record.
    #
    # + data - Field values to update.
    # + return - The updated generic record, or an error.
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
    #
    # + data - Field values to apply to all matching rows.
    # + return - Number of updated rows, or an error.
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
    #
    # + createData - Field values for the insert branch.
    # + updateData - Field values for the update branch.
    # + return - SQL execution result, or an error.
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
    #
    # **Note**: The fetch and delete are separate operations and are not atomic unless wrapped
    # in a Ballerina `transaction` block. In concurrent scenarios, the row may be modified or
    # deleted between the fetch and delete steps.
    #
    # + return - The deleted generic record, or an error.
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
    #
    # + return - Number of deleted rows, or an error.
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
#
# + dbClient - The ORM client to execute against.
# + plan - Compiled read query plan.
# + return - Array of result rows with snake_case keys converted to camelCase, or an error.
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
#
# + dbClient - The ORM client to query against.
# + tableName - The table to query.
# + rowId - The primary key value to look up.
# + return - The matching record row, nil if not found, or an error.
function fetchInsertedRow(Client dbClient, string tableName, string|int rowId) returns record {}?|error {
    anydata[] params = [rowId];
    string quotedTable = quoteIdentifier(dbClient.provider, tableName);
    string quotedId = quoteIdentifier(dbClient.provider, "id");
    string sql;
    if dbClient.provider == POSTGRESQL {
        sql = "SELECT * FROM " + quotedTable + " WHERE " + quotedId + " = $1 LIMIT 1";
    } else {
        sql = "SELECT * FROM " + quotedTable + " WHERE " + quotedId + " = ? LIMIT 1";
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

# Fetch multiple rows by auto-generated primary key range.
# Used internally after batch INSERT to return all inserted records.
#
# + dbClient - The ORM client to query against.
# + tableName - The table to query.
# + firstId - The first primary key value in the range.
# + count - The number of rows to fetch.
# + return - Array of matching record rows, or an error.
function fetchInsertedRows(Client dbClient, string tableName, int firstId, int count) returns record {}[]|error {
    int lastId = firstId + count - 1;
    anydata[] params = [firstId, lastId];
    string quotedTable = quoteIdentifier(dbClient.provider, tableName);
    string quotedId = quoteIdentifier(dbClient.provider, "id");
    string sql;
    if dbClient.provider == POSTGRESQL {
        sql = "SELECT * FROM " + quotedTable + " WHERE " + quotedId + " >= $1 AND " + quotedId + " <= $2 ORDER BY " + quotedId + " ASC";
    } else {
        sql = "SELECT * FROM " + quotedTable + " WHERE " + quotedId + " >= ? AND " + quotedId + " <= ? ORDER BY " + quotedId + " ASC";
    }
    stream<record {}, sql:Error?>|ClientError|sql:Error queryResult = dbClient.rawQuery(sql, params);
    if queryResult is error {
        return queryResult;
    }
    record {}[]|error rows = from var r in queryResult select r;
    if rows is error {
        return rows;
    }
    return (<record {}[]>rows).map(convertRowToCamel);
}

# For PostgreSQL: query the last inserted id using lastval().
#
# + dbClient - The ORM client connected to the PostgreSQL database.
# + return - The last auto-generated integer ID, or an error.
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
#
# + row - Source record with snake_case column keys.
# + return - New record with camelCase keys.
function convertRowToCamel(record {} row) returns record {} {
    map<anydata> result = {};
    foreach var [key, value] in row.entries() {
        result[snakeToCamel(key)] = value;
    }
    return result;
}

# Convert a snake_case string to camelCase.
# e.g. `created_at` → `createdAt`, `user_id` → `userId`
#
# + s - snake_case input string.
# + return - camelCase equivalent of the input string.
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
