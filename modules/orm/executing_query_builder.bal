import ballerina/sql;

# Fluent query builder that is pre-bound to a live ORM client.
# Terminal methods execute immediately — no separate query-runner step required.
#
# Obtain one via `db.model(ModelType)` rather than `orm:'from(ModelType)`.
#
# Example:
# ```ballerina
# record {}[] users = check db.model(User)
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

    # Execute the query and return all matching rows.
    public transactional function findMany() returns record {}[]|SchemaError|ClientError|sql:Error {
        self.plan.operation = FIND_MANY;
        return executeReadPlan(self.dbClient, self.plan);
    }

    # Execute the query and return the first matching row, or nil if none found.
    public transactional function findFirst() returns record {}?|SchemaError|ClientError|sql:Error {
        self.plan.operation = FIND_FIRST;
        self.plan.take = 1;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is record {}[] {
            return rows.length() > 0 ? rows[0] : ();
        }
        return rows;
    }

    # Execute the query and return the unique matching row, or nil if none found.
    public transactional function findUnique() returns record {}?|SchemaError|ClientError|sql:Error {
        self.plan.operation = FIND_UNIQUE;
        self.plan.take = 1;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is record {}[] {
            return rows.length() > 0 ? rows[0] : ();
        }
        return rows;
    }

    # Execute a count query and return the row count.
    public transactional function count() returns int|SchemaError|ClientError|sql:Error {
        self.plan.operation = COUNT;
        record {}[]|SchemaError|ClientError|sql:Error rows = executeReadPlan(self.dbClient, self.plan);
        if rows is record {}[] {
            if rows.length() > 0 {
                anydata countVal = rows[0]["count"];
                if countVal is int {
                    return countVal;
                }
            }
            return 0;
        }
        return rows;
    }

    # Execute a create query.
    public transactional function create(map<anydata> data) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = CREATE;
        self.plan.data = data;
        return self.dbClient.execute(self.plan);
    }

    # Execute a createMany query.
    public transactional function createMany(map<anydata>[] dataList) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = CREATE_MANY;
        self.plan.dataList = dataList;
        return self.dbClient.execute(self.plan);
    }

    # Execute an update query.
    public transactional function update(map<anydata> data) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = UPDATE;
        self.plan.data = data;
        return self.dbClient.execute(self.plan);
    }

    # Execute an updateMany query.
    public transactional function updateMany(map<anydata> data) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = UPDATE_MANY;
        self.plan.data = data;
        return self.dbClient.execute(self.plan);
    }

    # Execute an upsert query (insert if not exists, otherwise update).
    public transactional function upsert(map<anydata> createData, map<anydata> updateData) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = UPSERT;
        self.plan.upsert = {
            create: createData,
            update: updateData
        };
        return self.dbClient.execute(self.plan);
    }

    # Execute a delete query.
    public transactional function delete() returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = DELETE;
        return self.dbClient.execute(self.plan);
    }

    # Execute a deleteMany query.
    public transactional function deleteMany() returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        self.plan.operation = DELETE_MANY;
        return self.dbClient.execute(self.plan);
    }
}

# Shared helper: run a read QueryPlan and collect all rows.
transactional function executeReadPlan(Client dbClient, QueryPlan plan)
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
        return <record {}[]>rows;
    }
    return queryResult;
}
