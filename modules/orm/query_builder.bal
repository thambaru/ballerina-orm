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
public type UpsertInput record {|
    map<anydata> create;
    map<anydata> update;
|};

# Captured query plan produced by the builder.
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
public type SqlQuery record {|
    string text;
    anydata[] parameters = [];
|};

# Start a query builder from a model type descriptor.
public function 'from(typedesc<anydata> modelType) returns QueryBuilder {
    return new (extractModelName(modelType));
}

# Start a query builder from a model name.
public function fromModel(string modelName) returns QueryBuilder {
    return new (modelName);
}

# Build ad-hoc parameterized SQL query payload.
public function rawQuery(string text, anydata... params) returns SqlQuery {
    return {
        text,
        parameters: params
    };
}

# Build ad-hoc parameterized SQL execute payload.
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
    public function 'table(string tableName) returns QueryBuilder {
        self.plan.tableName = tableName;
        return self;
    }

    # Add a where filter.
    public function 'where(WhereInput whereInput) returns QueryBuilder {
        self.plan.'where = whereInput;
        return self;
    }

    # Add an order-by clause.
    public function orderBy(OrderByInput orderByInput) returns QueryBuilder {
        self.plan.orderBy.push(orderByInput);
        return self;
    }

    # Set result offset.
    public function skip(int value) returns QueryBuilder {
        self.plan.skip = value;
        return self;
    }

    # Set result size limit.
    public function take(int value) returns QueryBuilder {
        self.plan.take = value;
        return self;
    }

    # Add select projection.
    public function 'select(SelectInput selectInput) returns QueryBuilder {
        self.plan.'select = selectInput;
        return self;
    }

    # Add relation include payload.
    public function include(IncludeInput includeInput) returns QueryBuilder {
        self.plan.include = includeInput;
        return self;
    }

    # Build a find-many query plan.
    public function findMany() returns QueryPlan {
        self.plan.operation = FIND_MANY;
        return self.plan;
    }

    # Build a find-unique query plan.
    public function findUnique() returns QueryPlan {
        self.plan.operation = FIND_UNIQUE;
        if self.plan.take is () {
            self.plan.take = 1;
        }
        return self.plan;
    }

    # Build a find-first query plan.
    public function findFirst() returns QueryPlan {
        self.plan.operation = FIND_FIRST;
        self.plan.take = 1;
        return self.plan;
    }

    # Build a create query plan.
    public function create(map<anydata> data) returns QueryPlan {
        self.plan.operation = CREATE;
        self.plan.data = data;
        return self.plan;
    }

    # Build a create-many query plan.
    public function createMany(map<anydata>[] dataList) returns QueryPlan {
        self.plan.operation = CREATE_MANY;
        self.plan.dataList = dataList;
        return self.plan;
    }

    # Build an update query plan.
    public function update(map<anydata> data) returns QueryPlan {
        self.plan.operation = UPDATE;
        self.plan.data = data;
        return self.plan;
    }

    # Build an update-many query plan.
    public function updateMany(map<anydata> data) returns QueryPlan {
        self.plan.operation = UPDATE_MANY;
        self.plan.data = data;
        return self.plan;
    }

    # Build an upsert query plan.
    public function upsert(map<anydata> createData, map<anydata> updateData) returns QueryPlan {
        self.plan.operation = UPSERT;
        self.plan.upsert = {
            create: createData,
            update: updateData
        };
        return self.plan;
    }

    # Build a delete query plan.
    public function delete() returns QueryPlan {
        self.plan.operation = DELETE;
        return self.plan;
    }

    # Build a delete-many query plan.
    public function deleteMany() returns QueryPlan {
        self.plan.operation = DELETE_MANY;
        return self.plan;
    }

    # Build a count query plan.
    public function count() returns QueryPlan {
        self.plan.operation = COUNT;
        return self.plan;
    }

    # Build an aggregate query plan.
    public function aggregate(AggregateInput input) returns QueryPlan {
        self.plan.operation = AGGREGATE;
        self.plan.aggregate = input;
        return self.plan;
    }
}

# Best-effort model type name extraction from `typedesc` value.
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
