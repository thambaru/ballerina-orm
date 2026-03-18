# Convert a query plan into dialect-aware SQL and parameter bindings.

# Convert a query plan to SQL for the selected engine.
#
# + plan - Compiled query plan to convert.
# + engine - Target database engine that determines SQL dialect.
# + return - SQL text with positional parameters, or a SchemaError.
public function toSql(QueryPlan plan, Engine engine = MYSQL) returns SqlQuery|SchemaError {
    SqlBuildState state = new;
    string tableName = plan.tableName ?: toDefaultTableName(plan.model);

    if plan.operation == FIND_MANY || plan.operation == FIND_FIRST || plan.operation == FIND_UNIQUE {
        string selectSql = check buildSelectSql(plan, tableName, engine, state);
        return {
            text: selectSql,
            parameters: state.parameters
        };
    }

    if plan.operation == CREATE {
        map<anydata> payload = check requireData(plan, "CREATE");
        string createSql = check buildInsertSql(tableName, payload, engine, state);
        return {
            text: createSql,
            parameters: state.parameters
        };
    }

    if plan.operation == CREATE_MANY {
        map<anydata>[] payloadList = check requireDataList(plan);
        string createManySql = check buildInsertManySql(tableName, payloadList, engine, state);
        return {
            text: createManySql,
            parameters: state.parameters
        };
    }

    if plan.operation == UPDATE || plan.operation == UPDATE_MANY {
        map<anydata> payload = check requireData(plan, plan.operation);
        string updateSql = check buildUpdateSql(plan, tableName, payload, engine, state);
        return {
            text: updateSql,
            parameters: state.parameters
        };
    }

    if plan.operation == DELETE || plan.operation == DELETE_MANY {
        string deleteSql = check buildDeleteSql(plan, tableName, engine, state);
        return {
            text: deleteSql,
            parameters: state.parameters
        };
    }

    if plan.operation == COUNT {
        string countSql = check buildCountSql(plan, tableName, engine, state);
        return {
            text: countSql,
            parameters: state.parameters
        };
    }

    if plan.operation == AGGREGATE {
        AggregateInput aggregateInput = check requireAggregate(plan);
        string aggregateSql = check buildAggregateSql(plan, tableName, aggregateInput, engine, state);
        return {
            text: aggregateSql,
            parameters: state.parameters
        };
    }

    if plan.operation == UPSERT {
        UpsertInput upsertInput = check requireUpsert(plan);
        string upsertSql = check buildUpsertSql(plan, tableName, upsertInput, engine, state);
        return {
            text: upsertSql,
            parameters: state.parameters
        };
    }

    return schemaError("QUERY_OPERATION_UNSUPPORTED", string `Unsupported operation '${plan.operation}'.`, plan.model);
}

class SqlBuildState {
    public anydata[] parameters = [];
    public int parameterIndex = 1;
}

function requireData(QueryPlan plan, string op) returns map<anydata>|SchemaError {
    map<anydata>? payload = plan.data;
    if payload is map<anydata> {
        return payload;
    }
    return schemaError("QUERY_DATA_REQUIRED", string `${op} requires a non-empty data payload.`, plan.model);
}

function requireDataList(QueryPlan plan) returns map<anydata>[]|SchemaError {
    map<anydata>[]? payloadList = plan.dataList;
    if payloadList is map<anydata>[] {
        map<anydata>[] values = payloadList;
        if values.length() > 0 {
            return values;
        }
    }
    return schemaError("QUERY_DATA_LIST_REQUIRED", "CREATE_MANY requires a non-empty data list.", plan.model);
}

function requireAggregate(QueryPlan plan) returns AggregateInput|SchemaError {
    AggregateInput? aggregateInput = plan.aggregate;
    if aggregateInput is AggregateInput {
        return aggregateInput;
    }
    return schemaError("QUERY_AGGREGATE_REQUIRED", "AGGREGATE requires an aggregate payload.", plan.model);
}

function requireUpsert(QueryPlan plan) returns UpsertInput|SchemaError {
    UpsertInput? upsertInput = plan.upsert;
    if upsertInput is UpsertInput {
        return upsertInput;
    }
    return schemaError("QUERY_UPSERT_REQUIRED", "UPSERT requires create and update payloads.", plan.model);
}

function buildSelectSql(QueryPlan plan, string tableName, Engine engine, SqlBuildState state) returns string|SchemaError {
    IncludeInput? includeInput = plan.include;
    if includeInput is IncludeInput {
        string[] relations = includedRelations(includeInput);
        if relations.length() > 0 {
            return schemaError(
                "QUERY_INCLUDE_UNSUPPORTED",
                "Eager loading SQL generation is not implemented yet. Use separate relation queries.",
                plan.model
            );
        }
    }

    string projection = buildSelectProjection(plan.'select, engine);
    string sqlText = string `SELECT ${projection} FROM ${quoteIdentifier(engine, tableName)}`;

    WhereInput? whereInput = plan.'where;
    if whereInput is WhereInput {
        string whereSql = check buildWhereExpression(whereInput, engine, state);
        if whereSql != "" {
            sqlText = string `${sqlText} WHERE ${whereSql}`;
        }
    }

    if plan.orderBy.length() > 0 {
        string orderSql = buildOrderByClause(plan.orderBy, engine);
        if orderSql != "" {
            sqlText = string `${sqlText} ORDER BY ${orderSql}`;
        }
    }

    int? limitValue = plan.take;
    int? offsetValue = plan.skip;
    if plan.operation == FIND_FIRST || plan.operation == FIND_UNIQUE {
        limitValue = 1;
    }

    if limitValue is int {
        sqlText = string `${sqlText} LIMIT ${limitValue.toString()}`;
    }
    if offsetValue is int {
        sqlText = string `${sqlText} OFFSET ${offsetValue.toString()}`;
    }

    return sqlText;
}

function buildInsertSql(string tableName, map<anydata> payload, Engine engine, SqlBuildState state) returns string|SchemaError {
    if payload.length() == 0 {
        return schemaError("QUERY_DATA_REQUIRED", "CREATE requires at least one field.");
    }

    SchemaError? nestedWriteError = validateNoNestedWritePayload(payload);
    if nestedWriteError is SchemaError {
        return nestedWriteError;
    }

    string[] columnParts = [];
    string[] valueParts = [];

    foreach var [fieldName, value] in payload.entries() {
        columnParts.push(quoteIdentifier(engine, toSnakeCase(fieldName)));
        valueParts.push(addParam(engine, state, value));
    }

    string columnsSql = joinWithSeparator(columnParts, ", ");
    string valuesSql = joinWithSeparator(valueParts, ", ");
    return string `INSERT INTO ${quoteIdentifier(engine, tableName)} (${columnsSql}) VALUES (${valuesSql})`;
}

function buildInsertManySql(string tableName, map<anydata>[] payloadList, Engine engine, SqlBuildState state)
    returns string|SchemaError {
    map<anydata> firstRow = payloadList[0];
    if firstRow.length() == 0 {
        return schemaError("QUERY_DATA_REQUIRED", "CREATE_MANY rows must include at least one field.");
    }

    SchemaError? nestedWriteError = validateNoNestedWritePayload(firstRow);
    if nestedWriteError is SchemaError {
        return nestedWriteError;
    }

    string[] fields = [];
    foreach var [fieldName, _] in firstRow.entries() {
        fields.push(fieldName);
    }

    string[] quotedColumns = [];
    foreach string fieldName in fields {
        quotedColumns.push(quoteIdentifier(engine, toSnakeCase(fieldName)));
    }

    string[] rowGroups = [];
    foreach map<anydata> row in payloadList {
        SchemaError? rowNestedWriteError = validateNoNestedWritePayload(row);
        if rowNestedWriteError is SchemaError {
            return rowNestedWriteError;
        }

        string[] rowPlaceholders = [];
        foreach string fieldName in fields {
            anydata? value = row.get(fieldName);
            if value is () {
                return schemaError(
                    "QUERY_BULK_FIELD_MISMATCH",
                    string `CREATE_MANY row is missing field '${fieldName}'.`
                );
            }
            rowPlaceholders.push(addParam(engine, state, value));
        }
        rowGroups.push(string `(${joinWithSeparator(rowPlaceholders, ", ")})`);
    }

    string columnsSql = joinWithSeparator(quotedColumns, ", ");
    string valuesSql = joinWithSeparator(rowGroups, ", ");
    return string `INSERT INTO ${quoteIdentifier(engine, tableName)} (${columnsSql}) VALUES ${valuesSql}`;
}

function buildUpdateSql(QueryPlan plan, string tableName, map<anydata> payload, Engine engine, SqlBuildState state)
    returns string|SchemaError {
    if payload.length() == 0 {
        return schemaError("QUERY_DATA_REQUIRED", "UPDATE requires at least one field.", plan.model);
    }

    SchemaError? nestedWriteError = validateNoNestedWritePayload(payload);
    if nestedWriteError is SchemaError {
        return nestedWriteError;
    }

    string[] setParts = [];
    foreach var [fieldName, value] in payload.entries() {
        string columnName = quoteIdentifier(engine, toSnakeCase(fieldName));
        string placeholder = addParam(engine, state, value);
        setParts.push(string `${columnName} = ${placeholder}`);
    }

    string tableSql = quoteIdentifier(engine, tableName);
    string setSql = joinWithSeparator(setParts, ", ");
    string baseSql = string `UPDATE ${tableSql} SET ${setSql}`;

    string whereSql = "";
    WhereInput? whereInput = plan.'where;
    if whereInput is WhereInput {
        whereSql = check buildWhereExpression(whereInput, engine, state);
    }

    if plan.operation == UPDATE {
        if engine == POSTGRESQL {
            string subquery = string `SELECT ctid FROM ${tableSql}`;
            if whereSql != "" {
                subquery = string `${subquery} WHERE ${whereSql}`;
            }
            subquery = string `${subquery} LIMIT 1`;
            return string `${baseSql} WHERE ctid IN (${subquery})`;
        }

        if whereSql != "" {
            return string `${baseSql} WHERE ${whereSql} LIMIT 1`;
        }
        return string `${baseSql} LIMIT 1`;
    }

    if whereSql != "" {
        return string `${baseSql} WHERE ${whereSql}`;
    }
    return baseSql;
}

function buildDeleteSql(QueryPlan plan, string tableName, Engine engine, SqlBuildState state) returns string|SchemaError {
    string tableSql = quoteIdentifier(engine, tableName);
    string baseSql = string `DELETE FROM ${tableSql}`;

    string whereSql = "";
    WhereInput? whereInput = plan.'where;
    if whereInput is WhereInput {
        whereSql = check buildWhereExpression(whereInput, engine, state);
    }

    if plan.operation == DELETE {
        if engine == POSTGRESQL {
            string subquery = string `SELECT ctid FROM ${tableSql}`;
            if whereSql != "" {
                subquery = string `${subquery} WHERE ${whereSql}`;
            }
            subquery = string `${subquery} LIMIT 1`;
            return string `${baseSql} WHERE ctid IN (${subquery})`;
        }

        if whereSql != "" {
            return string `${baseSql} WHERE ${whereSql} LIMIT 1`;
        }
        return string `${baseSql} LIMIT 1`;
    }

    if whereSql != "" {
        return string `${baseSql} WHERE ${whereSql}`;
    }
    return baseSql;
}

function buildCountSql(QueryPlan plan, string tableName, Engine engine, SqlBuildState state) returns string|SchemaError {
    string sqlText = string `SELECT COUNT(*) AS ${quoteIdentifier(engine, "count")} FROM ${quoteIdentifier(engine, tableName)}`;
    WhereInput? whereInput = plan.'where;
    if whereInput is WhereInput {
        string whereSql = check buildWhereExpression(whereInput, engine, state);
        if whereSql != "" {
            sqlText = string `${sqlText} WHERE ${whereSql}`;
        }
    }
    return sqlText;
}

function buildAggregateSql(QueryPlan plan, string tableName, AggregateInput aggregateInput, Engine engine, SqlBuildState state)
    returns string|SchemaError {
    string[] projections = [];

    foreach var [aggregateKey, payload] in aggregateInput.entries() {
        if payload is map<anydata> {
            foreach var [fieldName, enabled] in payload.entries() {
                if enabled is boolean && enabled {
                    string column = quoteIdentifier(engine, toSnakeCase(fieldName));
                    if aggregateKey == "_count" {
                        projections.push(string `COUNT(${column}) AS ${quoteIdentifier(engine, fieldName + "_count")}`);
                    } else if aggregateKey == "_sum" {
                        projections.push(string `SUM(${column}) AS ${quoteIdentifier(engine, fieldName + "_sum")}`);
                    } else if aggregateKey == "_avg" {
                        projections.push(string `AVG(${column}) AS ${quoteIdentifier(engine, fieldName + "_avg")}`);
                    } else if aggregateKey == "_min" {
                        projections.push(string `MIN(${column}) AS ${quoteIdentifier(engine, fieldName + "_min")}`);
                    } else if aggregateKey == "_max" {
                        projections.push(string `MAX(${column}) AS ${quoteIdentifier(engine, fieldName + "_max")}`);
                    } else {
                        return schemaError(
                            "QUERY_AGGREGATE_UNSUPPORTED",
                            string `Unsupported aggregate key '${aggregateKey}'.`,
                            plan.model
                        );
                    }
                }
            }
        }
    }

    if projections.length() == 0 {
        return schemaError("QUERY_AGGREGATE_REQUIRED", "AGGREGATE requires at least one aggregate field.", plan.model);
    }

    string sqlText = string `SELECT ${joinWithSeparator(projections, ", ")} FROM ${quoteIdentifier(engine, tableName)}`;
    WhereInput? whereInput = plan.'where;
    if whereInput is WhereInput {
        string whereSql = check buildWhereExpression(whereInput, engine, state);
        if whereSql != "" {
            sqlText = string `${sqlText} WHERE ${whereSql}`;
        }
    }
    return sqlText;
}

function buildSelectProjection(SelectInput? selectInput, Engine engine) returns string {
    if selectInput is () {
        return "*";
    }

    string[] fields = selectedFields(selectInput);
    if fields.length() == 0 {
        return "*";
    }

    string[] columns = [];
    foreach string fieldName in fields {
        columns.push(quoteIdentifier(engine, toSnakeCase(fieldName)));
    }
    return joinWithSeparator(columns, ", ");
}

function buildOrderByClause(OrderByInput[] orderByInput, Engine engine) returns string {
    string[] items = [];
    foreach OrderByInput orderItem in orderByInput {
        foreach var [fieldName, direction] in orderItem.entries() {
            items.push(string `${quoteIdentifier(engine, toSnakeCase(fieldName))} ${direction}`);
        }
    }

    return joinWithSeparator(items, ", ");
}

function buildWhereExpression(WhereInput whereInput, Engine engine, SqlBuildState state) returns string|SchemaError {
    string[] expressions = [];

    foreach var [key, value] in whereInput.entries() {
        if key == "AND" || key == "OR" {
            string grouped = check buildLogicalGroup(key, value, engine, state);
            if grouped != "" {
                expressions.push(grouped);
            }
            continue;
        }

        if key == "NOT" {
            string negated = check buildNotGroup(value, engine, state);
            if negated != "" {
                expressions.push(negated);
            }
            continue;
        }

        string condition = check buildFieldCondition(key, value, engine, state);
        expressions.push(condition);
    }

    return joinWithSeparator(expressions, " AND ");
}

function buildLogicalGroup(string logicalOperator, anydata payload, Engine engine, SqlBuildState state) returns string|SchemaError {
    map<anydata>[] clauses = [];
    if payload is anydata[] {
        foreach anydata clausePayload in payload {
            map<anydata> clause = check toFilterMap(clausePayload, logicalOperator);
            clauses.push(clause);
        }
    } else {
        map<anydata> clause = check toFilterMap(payload, logicalOperator);
        clauses = [clause];
    }

    if clauses.length() == 0 {
        return "";
    }

    string[] rendered = [];
    foreach map<anydata> clause in clauses {
        string nested = check buildWhereExpression(clause, engine, state);
        if nested != "" {
            rendered.push(string `(${nested})`);
        }
    }

    if rendered.length() == 0 {
        return "";
    }

    string connector = logicalOperator == "OR" ? " OR " : " AND ";
    return string `(${joinWithSeparator(rendered, connector)})`;
}

function buildNotGroup(anydata payload, Engine engine, SqlBuildState state) returns string|SchemaError {
    if payload is anydata[] {
        string[] negatedItems = [];
        foreach anydata clausePayload in payload {
            map<anydata> clause = check toFilterMap(clausePayload, "NOT");
            string nested = check buildWhereExpression(clause, engine, state);
            if nested != "" {
                negatedItems.push(string `(NOT (${nested}))`);
            }
        }
        return joinWithSeparator(negatedItems, " AND ");
    }

    map<anydata> clause = check toFilterMap(payload, "NOT");
    string nested = check buildWhereExpression(clause, engine, state);
    if nested == "" {
        return "";
    }
    return string `(NOT (${nested}))`;
}

function toFilterMap(anydata payload, string operatorName) returns map<anydata>|SchemaError {
    if payload is map<anydata> {
        return payload;
    }

    if payload is record {} {
        map<anydata> converted = {};
        foreach var [key, entryValue] in payload.entries() {
            converted[key] = entryValue;
        }
        return converted;
    }

    return schemaError(
        "QUERY_LOGICAL_INVALID",
        string `'${operatorName}' expects a map or array of maps.`
    );
}

function buildFieldCondition(string fieldName, anydata value, Engine engine, SqlBuildState state) returns string|SchemaError {
    string column = quoteIdentifier(engine, toSnakeCase(fieldName));

    if value is map<anydata> {
        string conditions = check buildFieldOperatorConditions(column, value, engine, state);
        return string `(${conditions})`;
    }

    if value is () {
        return string `${column} IS NULL`;
    }

    string placeholder = addParam(engine, state, value);
    return string `${column} = ${placeholder}`;
}

function buildFieldOperatorConditions(string column, map<anydata> operators, Engine engine, SqlBuildState state)
    returns string|SchemaError {
    string[] conditions = [];
    foreach var [operator, operatorValue] in operators.entries() {
        string condition = check buildOperatorCondition(column, operator, operatorValue, engine, state);
        conditions.push(condition);
    }

    if conditions.length() == 0 {
        return schemaError("QUERY_OPERATOR_REQUIRED", "Field filter does not include operators.");
    }
    return joinWithSeparator(conditions, " AND ");
}

function buildOperatorCondition(string column, string operator, anydata value, Engine engine, SqlBuildState state)
    returns string|SchemaError {
    if operator == "equals" {
        if value is () {
            return string `${column} IS NULL`;
        }
        string placeholder = addParam(engine, state, value);
        return string `${column} = ${placeholder}`;
    }

    if operator == "not" {
        if value is map<anydata> {
            string inner = check buildFieldOperatorConditions(column, value, engine, state);
            return string `(NOT (${inner}))`;
        }
        if value is () {
            return string `${column} IS NOT NULL`;
        }
        string placeholder = addParam(engine, state, value);
        return string `${column} <> ${placeholder}`;
    }

    if operator == "in" || operator == "notIn" {
        if value !is anydata[] {
            return schemaError("QUERY_OPERATOR_VALUE_INVALID", string `'${operator}' expects an array.`);
        }

        anydata[] values = value;
        if values.length() == 0 {
            return operator == "in" ? "1 = 0" : "1 = 1";
        }

        string[] placeholders = [];
        foreach anydata item in values {
            placeholders.push(addParam(engine, state, item));
        }

        string sqlOp = operator == "in" ? "IN" : "NOT IN";
        return string `${column} ${sqlOp} (${joinWithSeparator(placeholders, ", ")})`;
    }

    if operator == "lt" || operator == "lte" || operator == "gt" || operator == "gte" {
        string sqlOp = operator == "lt" ? "<" : operator == "lte" ? "<=" : operator == "gt" ? ">" : ">=";
        string placeholder = addParam(engine, state, value);
        return string `${column} ${sqlOp} ${placeholder}`;
    }

    if operator == "contains" || operator == "startsWith" || operator == "endsWith" {
        if value !is string {
            return schemaError("QUERY_OPERATOR_VALUE_INVALID", string `'${operator}' expects a string.`);
        }

        string escapedValue = escapeLikePattern(value);
        string pattern = operator == "contains" ? string `%${escapedValue}%` :
            operator == "startsWith" ? string `${escapedValue}%` : string `%${escapedValue}`;
        string placeholder = addParam(engine, state, pattern);
        if engine == POSTGRESQL {
            // PostgreSQL with standard_conforming_strings=on (default since 9.1) uses backslash
            // as the default LIKE escape character. An explicit ESCAPE clause is intentionally
            // omitted because ESCAPE '\' is treated as a literal two-char string in standard mode.
            return string `${column} LIKE ${placeholder}`;
        }
        return string `${column} LIKE ${placeholder} ESCAPE '\\'`;
    }

    if operator == "isNull" {
        if value is boolean {
            return value ? string `${column} IS NULL` : string `${column} IS NOT NULL`;
        }
        return schemaError("QUERY_OPERATOR_VALUE_INVALID", "'isNull' expects a boolean value.");
    }

    return schemaError("QUERY_OPERATOR_UNSUPPORTED", string `Unsupported filter operator '${operator}'.`);
}

function addParam(Engine engine, SqlBuildState state, anydata value) returns string {
    state.parameters.push(value);
    string placeholder = engine == POSTGRESQL ? postgresqlPlaceholder(state.parameterIndex) : mysqlPlaceholder(state.parameterIndex);
    state.parameterIndex += 1;
    return placeholder;
}

function quoteIdentifier(Engine engine, string identifier) returns string {
    return engine == POSTGRESQL ? postgresqlQuoteIdentifier(identifier) : mysqlQuoteIdentifier(identifier);
}

function buildUpsertSql(QueryPlan plan, string tableName, UpsertInput upsertInput, Engine engine, SqlBuildState state)
    returns string|SchemaError {
    map<anydata> createPayload = upsertInput.create;
    map<anydata> updatePayload = upsertInput.update;

    if createPayload.length() == 0 {
        return schemaError("QUERY_DATA_REQUIRED", "UPSERT create payload must include at least one field.", plan.model);
    }
    if updatePayload.length() == 0 {
        return schemaError("QUERY_DATA_REQUIRED", "UPSERT update payload must include at least one field.", plan.model);
    }

    SchemaError? createNestedWriteError = validateNoNestedWritePayload(createPayload);
    if createNestedWriteError is SchemaError {
        return createNestedWriteError;
    }
    SchemaError? updateNestedWriteError = validateNoNestedWritePayload(updatePayload);
    if updateNestedWriteError is SchemaError {
        return updateNestedWriteError;
    }

    string insertSql = check buildInsertSql(tableName, createPayload, engine, state);

    string[] updateAssignments = [];
    foreach var [fieldName, value] in updatePayload.entries() {
        string columnName = quoteIdentifier(engine, toSnakeCase(fieldName));
        string placeholder = addParam(engine, state, value);
        updateAssignments.push(string `${columnName} = ${placeholder}`);
    }

    string updateSql = joinWithSeparator(updateAssignments, ", ");
    if engine == MYSQL {
        return string `${insertSql} ON DUPLICATE KEY UPDATE ${updateSql}`;
    }

    string[] conflictColumns = check inferPostgresqlConflictColumns(plan.'where, plan.model);
    string[] quotedConflictColumns = [];
    foreach string conflictColumn in conflictColumns {
        quotedConflictColumns.push(quoteIdentifier(engine, toSnakeCase(conflictColumn)));
    }

    string conflictTargetSql = joinWithSeparator(quotedConflictColumns, ", ");
    return string `${insertSql} ON CONFLICT (${conflictTargetSql}) DO UPDATE SET ${updateSql}`;
}

function inferPostgresqlConflictColumns(WhereInput? whereInput, string modelName) returns string[]|SchemaError {
    if whereInput is () {
        return schemaError(
            "QUERY_UPSERT_CONFLICT_REQUIRED",
            "PostgreSQL UPSERT requires a where filter with equality fields to infer ON CONFLICT columns.",
            modelName
        );
    }

    string[] conflictColumns = [];
    foreach var [fieldName, whereValue] in whereInput.entries() {
        if isLogicalWhereOperator(fieldName) {
            return schemaError(
                "QUERY_UPSERT_CONFLICT_INVALID",
                "PostgreSQL UPSERT conflict fields cannot use AND/OR/NOT operators.",
                modelName
            );
        }

        if whereValue is map<anydata> {
            if !whereValue.hasKey("equals") {
                return schemaError(
                    "QUERY_UPSERT_CONFLICT_INVALID",
                    string `PostgreSQL UPSERT conflict field '${fieldName}' must use equals.`,
                    modelName,
                    fieldName
                );
            }
        }

        conflictColumns.push(fieldName);
    }

    if conflictColumns.length() == 0 {
        return schemaError(
            "QUERY_UPSERT_CONFLICT_REQUIRED",
            "PostgreSQL UPSERT requires at least one equality field in where filter.",
            modelName
        );
    }

    return conflictColumns;
}

function escapeLikePattern(string value) returns string {
    string escaped = "";
    int index = 0;
    while index < value.length() {
        string current = value.substring(index, index + 1);
        if current == "\\" || current == "%" || current == "_" {
            escaped = escaped + "\\" + current;
        } else {
            escaped = string `${escaped}${current}`;
        }
        index += 1;
    }
    return escaped;
}

function validateNoNestedWritePayload(map<anydata> payload) returns SchemaError? {
    foreach var [_, value] in payload.entries() {
        if value is map<anydata> {
            if isNestedWriteDirective(value) {
                return schemaError(
                    "QUERY_NESTED_WRITE_UNSUPPORTED",
                    "Nested writes are not implemented yet. Execute parent and child writes separately."
                );
            }
        }
    }
    return;
}

function isNestedWriteDirective(map<anydata> payload) returns boolean {
    return payload.hasKey("create") || payload.hasKey("createMany") || payload.hasKey("update") ||
        payload.hasKey("upsert") || payload.hasKey("delete") || payload.hasKey("deleteMany") ||
        payload.hasKey("connect") || payload.hasKey("disconnect") || payload.hasKey("set");
}

function joinWithSeparator(string[] values, string separator) returns string {
    string out = "";
    foreach string value in values {
        if out == "" {
            out = value;
        } else {
            out = string `${out}${separator}${value}`;
        }
    }
    return out;
}
