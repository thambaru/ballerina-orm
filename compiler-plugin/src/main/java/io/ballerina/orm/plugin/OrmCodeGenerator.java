package io.ballerina.orm.plugin;

import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.ModuleMemberDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.RecordFieldNode;
import io.ballerina.compiler.syntax.tree.RecordFieldWithDefaultValueNode;
import io.ballerina.compiler.syntax.tree.RecordTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.SimpleNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.TypeDefinitionNode;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.Module;
import io.ballerina.projects.plugins.CodeGenerator;
import io.ballerina.projects.plugins.CodeGeneratorContext;
import io.ballerina.projects.plugins.SourceGeneratorContext;
import io.ballerina.tools.text.TextDocument;
import io.ballerina.tools.text.TextDocuments;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;

/**
 * Generates typed input records and CRUD wrapper functions at compile time.
 *
 * <p>This generator creates model-specific types ({@code UserCreateInput},
 * {@code UserWhereInput}, etc.) and CRUD helper functions (e.g., {@code userFindMany}).
 * The generation logic delegates to the {@code orm} module's runtime generator APIs.
 */
public class OrmCodeGenerator extends CodeGenerator {

    @Override
    public void init(CodeGeneratorContext context) {
        context.addSourceGeneratorTask(this::generateSources);
    }

    private void generateSources(SourceGeneratorContext context) {
        for (Module module : context.currentPackage().modules()) {
            List<ModelSpec> entityModels = collectEntityModels(module);
            for (ModelSpec modelSpec : entityModels) {
                String generatedSource = generateModelSource(modelSpec);
                TextDocument generatedDocument = TextDocuments.from(generatedSource);
                context.addSourceFile(generatedDocument, generatedFilePrefix(modelSpec.name), module.moduleId());
            }
        }
    }

    private List<ModelSpec> collectEntityModels(Module module) {
        List<ModelSpec> models = new ArrayList<>();
        for (DocumentId documentId : module.documentIds()) {
            ModulePartNode modulePartNode = module.document(documentId).syntaxTree().rootNode();
            for (ModuleMemberDeclarationNode member : modulePartNode.members()) {
                if (member.kind() != SyntaxKind.TYPE_DEFINITION) {
                    continue;
                }

                TypeDefinitionNode typeDefinitionNode = (TypeDefinitionNode) member;
                if (!hasOrmEntityAnnotation(typeDefinitionNode.metadata())) {
                    continue;
                }

                if (typeDefinitionNode.typeDescriptor().kind() != SyntaxKind.RECORD_TYPE_DESC) {
                    continue;
                }

                RecordTypeDescriptorNode recordTypeDescriptorNode = (RecordTypeDescriptorNode) typeDefinitionNode.typeDescriptor();
                ModelSpec modelSpec = new ModelSpec(normalizeIdentifier(typeDefinitionNode.typeName().text()));

                for (Node fieldNode : recordTypeDescriptorNode.fields()) {
                    if (fieldNode.kind() == SyntaxKind.RECORD_FIELD) {
                        RecordFieldNode recordFieldNode = (RecordFieldNode) fieldNode;
                        modelSpec.fields.add(buildFieldSpec(
                                normalizeIdentifier(recordFieldNode.fieldName().text()),
                                recordFieldNode.typeName().toSourceCode(),
                                recordFieldNode.metadata(),
                                recordFieldNode.questionMarkToken().isPresent(),
                                false));
                    }

                    if (fieldNode.kind() == SyntaxKind.RECORD_FIELD_WITH_DEFAULT_VALUE) {
                        RecordFieldWithDefaultValueNode fieldWithDefaultValueNode =
                                (RecordFieldWithDefaultValueNode) fieldNode;
                        modelSpec.fields.add(buildFieldSpec(
                                normalizeIdentifier(fieldWithDefaultValueNode.fieldName().text()),
                                fieldWithDefaultValueNode.typeName().toSourceCode(),
                                fieldWithDefaultValueNode.metadata(),
                                false,
                                true));
                    }
                }

                models.add(modelSpec);
            }
        }

        return models;
    }

    private FieldSpec buildFieldSpec(
            String fieldName,
            String rawType,
            Optional<MetadataNode> metadataNodeOptional,
            boolean optionalFromType,
            boolean hasDefaultValue) {

        FieldSpec fieldSpec = new FieldSpec();
        fieldSpec.name = fieldName;
        fieldSpec.rawType = normalizeType(rawType);
        fieldSpec.baseType = stripOptional(fieldSpec.rawType);
        fieldSpec.scalar = isScalarType(fieldSpec.baseType);
        fieldSpec.id = hasAnnotation(metadataNodeOptional, "Id");
        fieldSpec.autoIncrement = hasAnnotation(metadataNodeOptional, "AutoIncrement");
        fieldSpec.createdAt = hasAnnotation(metadataNodeOptional, "CreatedAt");
        fieldSpec.updatedAt = hasAnnotation(metadataNodeOptional, "UpdatedAt");
        fieldSpec.ignored = hasAnnotation(metadataNodeOptional, "Ignore");

        Optional<Boolean> nullableFromAnnotation = readColumnNullable(metadataNodeOptional);
        boolean nullableFromType = optionalFromType || fieldSpec.rawType.endsWith("?");
        fieldSpec.nullable = nullableFromAnnotation.orElse(nullableFromType);
        fieldSpec.hasDefault = hasDefaultValue;
        return fieldSpec;
    }

    private String generateModelSource(ModelSpec modelSpec) {
        String createInputTypeName = modelSpec.name + "CreateInput";
        String updateInputTypeName = modelSpec.name + "UpdateInput";
        String whereInputTypeName = modelSpec.name + "WhereInput";
        String orderByInputTypeName = modelSpec.name + "OrderByInput";
        String includeTypeName = modelSpec.name + "Include";
        String token = lowerFirst(modelSpec.name);

        StringBuilder source = new StringBuilder();
        source.append("import thambaru/bal_orm.orm;\n\n");

        source.append(generateCreateInputType(modelSpec, createInputTypeName));
        source.append("\n\n");
        source.append(generateUpdateInputType(modelSpec, updateInputTypeName));
        source.append("\n\n");

        List<String> filterTypeNames = new ArrayList<>();
        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isWhereOrderEligible(fieldSpec)) {
                continue;
            }

            String filterTypeName = modelSpec.name + upperFirst(fieldSpec.name) + "Filter";
            filterTypeNames.add(filterTypeName);
            source.append(generateFilterType(filterTypeName, fieldSpec));
            source.append("\n\n");
        }

        source.append(generateWhereInputType(modelSpec, whereInputTypeName));
        source.append("\n\n");
        source.append(generateOrderByInputType(modelSpec, orderByInputTypeName));
        source.append("\n\n");
        source.append(generateIncludeType(modelSpec, includeTypeName));
        source.append("\n\n");

        source.append(generateCreateDataMapper(modelSpec, createInputTypeName, token));
        source.append("\n\n");
        source.append(generateUpdateDataMapper(modelSpec, updateInputTypeName, token));
        source.append("\n\n");

        source.append("public function ").append(token).append("FindMany(")
                .append(whereInputTypeName)
                .append("? whereInput = ()) returns orm:QueryPlan {\n")
                .append("    orm:QueryBuilder builder = orm:fromModel(\"")
                .append(escapeStringLiteral(modelSpec.name))
                .append("\");\n")
                .append("    if whereInput is ").append(whereInputTypeName).append(" {\n")
                .append("        builder = builder.'where(whereInput);\n")
                .append("    }\n")
                .append("    return builder.findMany();\n")
                .append("}\n\n");

        source.append("public function ").append(token).append("FindUnique(")
                .append(whereInputTypeName)
                .append(" whereInput) returns orm:QueryPlan {\n")
                .append("    return orm:fromModel(\"")
                .append(escapeStringLiteral(modelSpec.name))
                .append("\").'where(whereInput).findUnique();\n")
                .append("}\n\n");

        source.append("public function ").append(token).append("Create(")
                .append(createInputTypeName)
                .append(" payload) returns orm:QueryPlan {\n")
                .append("    return orm:fromModel(\"")
                .append(escapeStringLiteral(modelSpec.name))
                .append("\").create(")
                .append(token)
                .append("ToCreateData(payload));\n")
                .append("}\n\n");

        source.append("public function ").append(token).append("Update(")
                .append(whereInputTypeName)
                .append(" whereInput, ")
                .append(updateInputTypeName)
                .append(" payload) returns orm:QueryPlan {\n")
                .append("    return orm:fromModel(\"")
                .append(escapeStringLiteral(modelSpec.name))
                .append("\").'where(whereInput).update(")
                .append(token)
                .append("ToUpdateData(payload));\n")
                .append("}\n\n");

        source.append("public function ").append(token).append("Delete(")
                .append(whereInputTypeName)
                .append(" whereInput) returns orm:QueryPlan {\n")
                .append("    return orm:fromModel(\"")
                .append(escapeStringLiteral(modelSpec.name))
                .append("\").'where(whereInput).delete();\n")
                .append("}\n");

        return source.toString();
    }

    private String generateCreateInputType(ModelSpec modelSpec, String typeName) {
        List<String> lines = new ArrayList<>();

        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isCreateField(fieldSpec)) {
                continue;
            }

            String fieldType = stripOptional(fieldSpec.rawType);
            String optionalMarker = (!fieldSpec.nullable && !fieldSpec.hasDefault) ? "" : "?";
            lines.add("    " + fieldType + " " + emitFieldIdentifier(fieldSpec.name) + optionalMarker + ";");
        }

        return buildRecordTypeSource(typeName, lines);
    }

    private String generateUpdateInputType(ModelSpec modelSpec, String typeName) {
        List<String> lines = new ArrayList<>();

        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isUpdateField(fieldSpec)) {
                continue;
            }

            String fieldType = stripOptional(fieldSpec.rawType);
            if (fieldSpec.nullable && !fieldType.endsWith("?")) {
                fieldType = fieldType + "?";
            }
            lines.add("    " + fieldType + " " + emitFieldIdentifier(fieldSpec.name) + "?;");
        }

        return buildRecordTypeSource(typeName, lines);
    }

    private String generateFilterType(String typeName, FieldSpec fieldSpec) {
        String valueType = stripOptional(fieldSpec.rawType);
        List<String> lines = new ArrayList<>();
        lines.add("    " + valueType + "? equals;");
        lines.add("    " + valueType + "? not;");
        lines.add("    " + valueType + "[]? 'in;");
        lines.add("    " + valueType + "[]? notIn;");

        FilterKind filterKind = resolveFilterKind(valueType);
        if (filterKind == FilterKind.INT || filterKind == FilterKind.NUMBER) {
            lines.add("    " + valueType + "? lt;");
            lines.add("    " + valueType + "? lte;");
            lines.add("    " + valueType + "? gt;");
            lines.add("    " + valueType + "? gte;");
        }

        if (filterKind == FilterKind.STRING) {
            lines.add("    string? contains;");
            lines.add("    string? startsWith;");
            lines.add("    string? endsWith;");
        }

        lines.add("    boolean? isNull;");
        return buildRecordTypeSource(typeName, lines);
    }

    private String generateWhereInputType(ModelSpec modelSpec, String typeName) {
        List<String> lines = new ArrayList<>();
        lines.add("    " + typeName + "[]? AND;");
        lines.add("    " + typeName + "[]? OR;");
        lines.add("    " + typeName + "? NOT;");

        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isWhereOrderEligible(fieldSpec)) {
                continue;
            }

            String filterTypeName = modelSpec.name + upperFirst(fieldSpec.name) + "Filter";
            lines.add("    " + stripOptional(fieldSpec.rawType) + "|" + filterTypeName + " "
                    + emitFieldIdentifier(fieldSpec.name) + "?;");
        }

        return buildRecordTypeSource(typeName, lines);
    }

    private String generateOrderByInputType(ModelSpec modelSpec, String typeName) {
        List<String> lines = new ArrayList<>();
        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isWhereOrderEligible(fieldSpec)) {
                continue;
            }
            lines.add("    orm:SortDirection " + emitFieldIdentifier(fieldSpec.name) + "?;");
        }

        return buildRecordTypeSource(typeName, lines);
    }

    private String generateIncludeType(ModelSpec modelSpec, String typeName) {
        List<String> lines = new ArrayList<>();
        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!fieldSpec.scalar && !fieldSpec.ignored) {
                lines.add("    boolean " + emitFieldIdentifier(fieldSpec.name) + "?;");
            }
        }

        return buildRecordTypeSource(typeName, lines);
    }

    private String generateCreateDataMapper(ModelSpec modelSpec, String createInputTypeName, String token) {
        StringBuilder source = new StringBuilder();
        source.append("function ").append(token).append("ToCreateData(")
                .append(createInputTypeName)
                .append(" payload) returns map<anydata> {\n")
                .append("    map<anydata> data = {};\n");

        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isCreateField(fieldSpec)) {
                continue;
            }

            String fieldAccess = emitFieldIdentifier(fieldSpec.name);
            String dataKey = escapeStringLiteral(fieldSpec.name);
            if (!fieldSpec.nullable && !fieldSpec.hasDefault) {
                source.append("    data[\"").append(dataKey).append("\"] = payload.")
                        .append(fieldAccess).append(";\n");
            } else {
                source.append("    if payload.").append(fieldAccess).append(" is anydata {\n")
                        .append("        data[\"").append(dataKey).append("\"] = payload.")
                        .append(fieldAccess).append(";\n")
                        .append("    }\n");
            }
        }

        source.append("    return data;\n")
                .append("}");
        return source.toString();
    }

    private String generateUpdateDataMapper(ModelSpec modelSpec, String updateInputTypeName, String token) {
        StringBuilder source = new StringBuilder();
        source.append("function ").append(token).append("ToUpdateData(")
                .append(updateInputTypeName)
                .append(" payload) returns map<anydata> {\n")
                .append("    map<anydata> data = {};\n");

        for (FieldSpec fieldSpec : modelSpec.fields) {
            if (!isUpdateField(fieldSpec)) {
                continue;
            }

            String fieldAccess = emitFieldIdentifier(fieldSpec.name);
            source.append("    if payload.").append(fieldAccess).append(" is anydata {\n")
                    .append("        data[\"").append(escapeStringLiteral(fieldSpec.name)).append("\"] = payload.")
                    .append(fieldAccess).append(";\n")
                    .append("    }\n");
        }

        source.append("    return data;\n")
                .append("}");
        return source.toString();
    }

    private String buildRecordTypeSource(String typeName, List<String> lines) {
        if (lines.isEmpty()) {
            lines.add("    anydata __placeholder?;");
        }

        StringBuilder source = new StringBuilder();
        source.append("public type ").append(typeName).append(" record {|\n");
        for (String line : lines) {
            source.append(line).append("\n");
        }
        source.append("|};");
        return source.toString();
    }

    private String generatedFilePrefix(String modelName) {
        return "orm_" + modelName.toLowerCase(Locale.ROOT) + "_generated";
    }

    private boolean isCreateField(FieldSpec fieldSpec) {
        return fieldSpec.scalar && !fieldSpec.ignored && !fieldSpec.autoIncrement && !fieldSpec.createdAt
                && !fieldSpec.updatedAt;
    }

    private boolean isUpdateField(FieldSpec fieldSpec) {
        return fieldSpec.scalar && !fieldSpec.ignored && !fieldSpec.autoIncrement && !fieldSpec.createdAt
                && !fieldSpec.updatedAt && !fieldSpec.id;
    }

    private boolean isWhereOrderEligible(FieldSpec fieldSpec) {
        return fieldSpec.scalar && !fieldSpec.ignored;
    }

    private Optional<Boolean> readColumnNullable(Optional<MetadataNode> metadataNodeOptional) {
        if (metadataNodeOptional.isEmpty()) {
            return Optional.empty();
        }

        for (AnnotationNode annotationNode : metadataNodeOptional.get().annotations()) {
            if (!isAnnotationName(annotationNode, "Column")) {
                continue;
            }

            Optional<MappingConstructorExpressionNode> mappingOptional = annotationNode.annotValue();
            if (mappingOptional.isEmpty()) {
                return Optional.empty();
            }

            for (MappingFieldNode mappingFieldNode : mappingOptional.get().fields()) {
                if (mappingFieldNode.kind() != SyntaxKind.SPECIFIC_FIELD) {
                    continue;
                }

                SpecificFieldNode specificFieldNode = (SpecificFieldNode) mappingFieldNode;
                String fieldName = normalizeIdentifier(specificFieldNode.fieldName().toSourceCode().trim());
                if (!"nullable".equals(fieldName) || specificFieldNode.valueExpr().isEmpty()) {
                    continue;
                }

                String value = specificFieldNode.valueExpr().get().toSourceCode().trim();
                if ("true".equals(value)) {
                    return Optional.of(true);
                }

                if ("false".equals(value)) {
                    return Optional.of(false);
                }
            }
        }

        return Optional.empty();
    }

    private boolean hasOrmEntityAnnotation(Optional<MetadataNode> metadataNodeOptional) {
        return hasAnnotation(metadataNodeOptional, "Entity");
    }

    private boolean hasAnnotation(Optional<MetadataNode> metadataNodeOptional, String annotationName) {
        if (metadataNodeOptional.isEmpty()) {
            return false;
        }

        for (AnnotationNode annotationNode : metadataNodeOptional.get().annotations()) {
            if (isAnnotationName(annotationNode, annotationName)) {
                return true;
            }
        }
        return false;
    }

    private boolean isAnnotationName(AnnotationNode annotationNode, String expectedName) {
        Node annotationReference = annotationNode.annotReference();
        if (annotationReference.kind() == SyntaxKind.QUALIFIED_NAME_REFERENCE) {
            QualifiedNameReferenceNode qualifiedNameReferenceNode = (QualifiedNameReferenceNode) annotationReference;
            return expectedName.equals(normalizeIdentifier(qualifiedNameReferenceNode.identifier().text()));
        }

        if (annotationReference.kind() == SyntaxKind.SIMPLE_NAME_REFERENCE) {
            SimpleNameReferenceNode simpleNameReferenceNode = (SimpleNameReferenceNode) annotationReference;
            return expectedName.equals(normalizeIdentifier(simpleNameReferenceNode.name().text()));
        }

        return false;
    }

    private FilterKind resolveFilterKind(String typeName) {
        String normalizedType = typeName.toLowerCase(Locale.ROOT);
        if (normalizedType.equals("int") || normalizedType.equals("byte")) {
            return FilterKind.INT;
        }

        if (normalizedType.equals("float") || normalizedType.equals("decimal")) {
            return FilterKind.NUMBER;
        }

        if (normalizedType.equals("string")) {
            return FilterKind.STRING;
        }

        if (normalizedType.equals("boolean")) {
            return FilterKind.BOOLEAN;
        }

        return FilterKind.OTHER;
    }

    private boolean isScalarType(String typeName) {
        String normalizedType = normalizeType(typeName);
        if (normalizedType.endsWith("[]")) {
            return false;
        }

        if (normalizedType.contains("|")) {
            String[] members = normalizedType.split("\\|");
            for (String member : members) {
                String value = normalizeType(member);
                if (value.isEmpty() || "()".equals(value)) {
                    continue;
                }

                if (!isScalarType(value)) {
                    return false;
                }
            }
            return true;
        }

        String baseType = stripOptional(normalizedType);
        if (baseType.equals("int") || baseType.equals("byte") || baseType.equals("float")
                || baseType.equals("decimal") || baseType.equals("string") || baseType.equals("boolean")
                || baseType.equals("json") || baseType.equals("xml") || baseType.equals("anydata")) {
            return true;
        }

        if (baseType.startsWith("time:")) {
            return true;
        }

        if (baseType.contains(":")) {
            return false;
        }

        if (baseType.isEmpty()) {
            return false;
        }

        return Character.isLowerCase(baseType.charAt(0));
    }

    private String normalizeType(String typeName) {
        return typeName.replace("\n", " ").replace("\r", " ").trim();
    }

    private String stripOptional(String typeName) {
        String value = normalizeType(typeName);
        while (value.endsWith("?")) {
            value = value.substring(0, value.length() - 1).trim();
        }
        return value;
    }

    private String normalizeIdentifier(String identifier) {
        String trimmedIdentifier = identifier.trim();
        if (trimmedIdentifier.startsWith("'")) {
            return trimmedIdentifier.substring(1);
        }
        return trimmedIdentifier;
    }

    private String emitFieldIdentifier(String fieldName) {
        if (fieldName.startsWith("'")) {
            return fieldName;
        }

        if (BALLERINA_KEYWORDS.contains(fieldName)) {
            return "'" + fieldName;
        }
        return fieldName;
    }

    private String lowerFirst(String value) {
        if (value.isEmpty()) {
            return value;
        }
        return Character.toLowerCase(value.charAt(0)) + value.substring(1);
    }

    private String upperFirst(String value) {
        if (value.isEmpty()) {
            return value;
        }
        return Character.toUpperCase(value.charAt(0)) + value.substring(1);
    }

    private String escapeStringLiteral(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private static final Set<String> BALLERINA_KEYWORDS = Set.of(
            "from", "where", "select", "table", "in", "equals", "order", "group", "by", "join",
            "limit", "type", "function", "transaction", "check", "error"
    );

    private enum FilterKind {
        INT,
        NUMBER,
        STRING,
        BOOLEAN,
        OTHER
    }

    private static final class ModelSpec {
        private final String name;
        private final List<FieldSpec> fields;

        private ModelSpec(String name) {
            this.name = name;
            this.fields = new ArrayList<>();
        }
    }

    private static final class FieldSpec {
        private String name;
        private String rawType;
        private String baseType;
        private boolean scalar;
        private boolean nullable;
        private boolean hasDefault;
        private boolean id;
        private boolean autoIncrement;
        private boolean createdAt;
        private boolean updatedAt;
        private boolean ignored;
    }
    }
}
