# Fluent query builder API for model-scoped operations.

# Query operation names.
public const FIND_MANY = "findMany";
public const FIND_UNIQUE = "findUnique";
public const FIND_FIRST = "findFirst";
public const CREATE = "create";
public const CREATE_MANY = "createMany";
public const UPDATE = "update";
public const UPDATE_MANY = "updateMany";
public const UPSERT = "upsert";
public const DELETE = "delete";
public const DELETE_MANY = "deleteMany";
public const COUNT = "count";
public const AGGREGATE = "aggregate";

# Supported query operation type.
public type QueryOperation
    FIND_MANY|FIND_UNIQUE|FIND_FIRST|CREATE|CREATE_MANY|UPDATE|UPDATE_MANY|UPSERT|DELETE|DELETE_MANY|COUNT|AGGREGATE;

# Upsert payload.
#
# + create - Data for the insert branch.
# + update - Data for the update branch.
public type UpsertInput record {|
    map<anydata> create;
    map<anydata> update;
|};

# Captured query plan produced by the builder.
#
# + model - Model name the query targets.
# + tableName - Optional explicit table name override.
# + operation - Query operation to perform.
# + where - Filter predicate.
# + orderBy - Ordered list of order-by clauses.
# + skip - Number of rows to skip (OFFSET).
# + take - Maximum number of rows to return (LIMIT).
# + select - Field projection payload.
# + include - Relation include payload.
# + data - Write payload for create, update, or upsert operations.
# + dataList - List of write payloads for createMany.
# + upsert - Separate create/update payloads for upsert.
# + aggregate - Aggregation input.
public type QueryPlan record {|
    string model;
    string? tableName = ();
    QueryOperation operation = FIND_MANY;
    WhereInput? 'where = ();
    OrderByInput[] orderBy = [];
    int? skip = ();
    int? take = ();
    SelectInput? 'select = ();
    IncludeInput? include = ();
    map<anydata>? data = ();
    map<anydata>[]? dataList = ();
    UpsertInput? upsert = ();
    AggregateInput? aggregate = ();
|};

# SQL payload produced by SQL generation.
#
# + text - SQL string with dialect-specific placeholders.
# + parameters - Ordered list of parameter values matching the placeholders.
public type SqlQuery record {|
    string text;
    anydata[] parameters = [];
|};

# Start a query builder from a model type descriptor.
#
# + modelType - Type descriptor of the model record type.
# + return - A new QueryBuilder scoped to the inferred model name.
public function 'from(typedesc<anydata> modelType) returns QueryBuilder {
    return new (extractModelName(modelType));
}

# Start a query builder from a model name.
#
# + modelName - Explicit model name string.
# + return - A new QueryBuilder scoped to the given model name.
public function fromModel(string modelName) returns QueryBuilder {
    return new (modelName);
}

# Build ad-hoc parameterized SQL query payload.
#
# + text - Raw SQL query string with placeholders.
# + params - Positional parameter values.
# + return - A SqlQuery payload ready for execution.
public function rawQuery(string text, anydata... params) returns SqlQuery {
    return {
        text,
        parameters: params
    };
}

# Build ad-hoc parameterized SQL execute payload.
#
# + text - Raw SQL statement string with placeholders.
# + params - Positional parameter values.
# + return - A SqlQuery payload ready for execution.
public function rawExecute(string text, anydata... params) returns SqlQuery {
    return {
        text,
        parameters: params
    };
}

# Mutable fluent query builder.
public class QueryBuilder {
    private QueryPlan plan;

    public function init(string modelName, string? tableName = ()) {
        self.plan = {
            model: modelName
        };
        if tableName is string {
            self.plan.tableName = tableName;
        }
    }

    # Override table name for this query.
    #
    # + tableName - Custom table name to use instead of the model-derived default.
    # + return - Updated builder with the custom table name applied.
    public function 'table(string tableName) returns QueryBuilder {
        self.plan.tableName = tableName;
        return self;
    }

    # Add a where filter.
    #
    # + whereInput - Filter predicate map.
    # + return - Updated builder with the where clause applied.
    public function 'where(WhereInput whereInput) returns QueryBuilder {
        self.plan.'where = whereInput;
        return self;
    }

    # Add an order-by clause.
    #
    # + orderByInput - Field-to-direction map specifying sort order.
    # + return - Updated builder with the order-by clause appended.
    public function orderBy(OrderByInput orderByInput) returns QueryBuilder {
        self.plan.orderBy.push(orderByInput);
        return self;
    }

    # Set result offset.
    #
    # + value - Number of rows to skip.
    # + return - Updated builder with the skip value set.
    public function skip(int value) returns QueryBuilder {
        self.plan.skip = value;
        return self;
    }

    # Set result size limit.
    #
    # + value - Maximum number of rows to return.
    # + return - Updated builder with the take value set.
    public function take(int value) returns QueryBuilder {
        self.plan.take = value;
        return self;
    }

    # Add select projection.
    #
    # + selectInput - Field projection map.
    # + return - Updated builder with the select projection applied.
    public function 'select(SelectInput selectInput) returns QueryBuilder {
        self.plan.'select = selectInput;
        return self;
    }

    # Add relation include payload.
    #
    # + includeInput - Relation include map.
    # + return - Updated builder with the include clause applied.
    public function include(IncludeInput includeInput) returns QueryBuilder {
        self.plan.include = includeInput;
        return self;
    }

    # Build a find-many query plan.
    #
    # + return - Compiled QueryPlan for a FIND_MANY operation.
    public function findMany() returns QueryPlan {
        self.plan.operation = FIND_MANY;
        return self.plan;
    }

    # Build a find-unique query plan.
    #
    # + return - Compiled QueryPlan for a FIND_UNIQUE operation.
    public function findUnique() returns QueryPlan {
        self.plan.operation = FIND_UNIQUE;
        if self.plan.take is () {
            self.plan.take = 1;
        }
        return self.plan;
    }

    # Build a find-first query plan.
    #
    # + return - Compiled QueryPlan for a FIND_FIRST operation.
    public function findFirst() returns QueryPlan {
        self.plan.operation = FIND_FIRST;
        self.plan.take = 1;
        return self.plan;
    }

    # Build a create query plan.
    #
    # + data - Field values to insert.
    # + return - Compiled QueryPlan for a CREATE operation.
    public function create(map<anydata> data) returns QueryPlan {
        self.plan.operation = CREATE;
        self.plan.data = data;
        return self.plan;
    }

    # Build a create-many query plan.
    #
    # + dataList - List of field value maps to insert.
    # + return - Compiled QueryPlan for a CREATE_MANY operation.
    public function createMany(map<anydata>[] dataList) returns QueryPlan {
        self.plan.operation = CREATE_MANY;
        self.plan.dataList = dataList;
        return self.plan;
    }

    # Build an update query plan.
    #
    # + data - Field values to update.
    # + return - Compiled QueryPlan for an UPDATE operation.
    public function update(map<anydata> data) returns QueryPlan {
        self.plan.operation = UPDATE;
        self.plan.data = data;
        return self.plan;
    }

    # Build an update-many query plan.
    #
    # + data - Field values to apply to all matching rows.
    # + return - Compiled QueryPlan for an UPDATE_MANY operation.
    public function updateMany(map<anydata> data) returns QueryPlan {
        self.plan.operation = UPDATE_MANY;
        self.plan.data = data;
        return self.plan;
    }

    # Build an upsert query plan.
    #
    # + createData - Field values used for the insert branch.
    # + updateData - Field values used for the update branch.
    # + return - Compiled QueryPlan for an UPSERT operation.
    public function upsert(map<anydata> createData, map<anydata> updateData) returns QueryPlan {
        self.plan.operation = UPSERT;
        self.plan.upsert = {
            create: createData,
            update: updateData
        };
        return self.plan;
    }

    # Build a delete query plan.
    #
    # + return - Compiled QueryPlan for a DELETE operation.
    public function delete() returns QueryPlan {
        self.plan.operation = DELETE;
        return self.plan;
    }

    # Build a delete-many query plan.
    #
    # + return - Compiled QueryPlan for a DELETE_MANY operation.
    public function deleteMany() returns QueryPlan {
        self.plan.operation = DELETE_MANY;
        return self.plan;
    }

    # Build a count query plan.
    #
    # + return - Compiled QueryPlan for a COUNT operation.
    public function count() returns QueryPlan {
        self.plan.operation = COUNT;
        return self.plan;
    }

    # Build an aggregate query plan.
    #
    # + input - Aggregation descriptor map.
    # + return - Compiled QueryPlan for an AGGREGATE operation.
    public function aggregate(AggregateInput input) returns QueryPlan {
        self.plan.operation = AGGREGATE;
        self.plan.aggregate = input;
        return self.plan;
    }
}

# Best-effort model type name extraction from `typedesc` value.
#
# + modelType - Type descriptor whose name is extracted.
# + return - The simple model name string (e.g. `"User"`).
function extractModelName(typedesc<anydata> modelType) returns string {
    string typeString = modelType.toString().trim();
    int end = typeString.length();
    while end > 0 {
        string c = typeString.substring(end - 1, end);
        if isIdentifierChar(c) {
            break;
        }
        end -= 1;
    }

    int startIndex = end;
    while startIndex > 0 {
        string c = typeString.substring(startIndex - 1, startIndex);
        if !isIdentifierChar(c) {
            break;
        }
        startIndex -= 1;
    }

    if startIndex < end {
        return typeString.substring(startIndex, end);
    }

    int? moduleSeparator = typeString.lastIndexOf(":");
    if moduleSeparator is int {
        return typeString.substring(moduleSeparator + 1);
    }

    return typeString;
}

function isIdentifierChar(string value) returns boolean {
    return (value >= "a" && value <= "z") ||
        (value >= "A" && value <= "Z") ||
        (value >= "0" && value <= "9") ||
        value == "_";
}
