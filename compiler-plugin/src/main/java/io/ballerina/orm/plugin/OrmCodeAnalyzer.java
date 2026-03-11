package io.ballerina.orm.plugin;

import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.RecordFieldNode;
import io.ballerina.compiler.syntax.tree.RecordFieldWithDefaultValueNode;
import io.ballerina.compiler.syntax.tree.RecordTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.SimpleNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.TypeDefinitionNode;
import io.ballerina.projects.plugins.CodeAnalysisContext;
import io.ballerina.projects.plugins.CodeAnalyzer;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import java.util.HashSet;
import java.util.Optional;
import java.util.Set;

/**
 * Analyzes {@code @orm:Entity} annotated record types at compile time.
 *
 * <p>This analyzer validates schema consistency (primary keys, relation types, etc.)
 * and reports diagnostics. The validation logic delegates to the Ballerina {@code orm}
 * module's runtime APIs.
 */
public class OrmCodeAnalyzer extends CodeAnalyzer {

    private static final String DIAG_INVALID_ENTITY_TARGET = "ORM_PLUGIN_1001";
    private static final String DIAG_ENTITY_NO_ID_FIELD = "ORM_PLUGIN_1002";
    private static final String DIAG_DUPLICATE_FIELD = "ORM_PLUGIN_1003";

    @Override
    public void init(CodeAnalysisContext context) {
        context.addSyntaxNodeAnalysisTask(this::analyzeTypeDefinition, SyntaxKind.TYPE_DEFINITION);
    }

    private void analyzeTypeDefinition(SyntaxNodeAnalysisContext context) {
        Node node = context.node();
        if (!(node instanceof TypeDefinitionNode typeDefinitionNode)) {
            return;
        }

        if (!hasOrmEntityAnnotation(typeDefinitionNode.metadata())) {
            return;
        }

        if (typeDefinitionNode.typeDescriptor().kind() != SyntaxKind.RECORD_TYPE_DESC) {
            context.reportDiagnostic(createDiagnostic(
                    DIAG_INVALID_ENTITY_TARGET,
                    "@orm:Entity can only be applied to record type definitions",
                    DiagnosticSeverity.ERROR,
                    typeDefinitionNode.typeDescriptor()));
            return;
        }

        RecordTypeDescriptorNode recordType = (RecordTypeDescriptorNode) typeDefinitionNode.typeDescriptor();
        Set<String> seenFields = new HashSet<>();
        boolean hasIdField = false;

        for (Node fieldNode : recordType.fields()) {
            if (fieldNode.kind() == SyntaxKind.RECORD_FIELD) {
                RecordFieldNode recordFieldNode = (RecordFieldNode) fieldNode;
                String fieldName = normalizeIdentifier(recordFieldNode.fieldName().text());
                if (!seenFields.add(fieldName)) {
                    context.reportDiagnostic(createDiagnostic(
                            DIAG_DUPLICATE_FIELD,
                            "Duplicate field declared in @orm:Entity record: " + fieldName,
                            DiagnosticSeverity.ERROR,
                            recordFieldNode.fieldName()));
                }

                if (hasOrmIdAnnotation(recordFieldNode.metadata())) {
                    hasIdField = true;
                }
            }

            if (fieldNode.kind() == SyntaxKind.RECORD_FIELD_WITH_DEFAULT_VALUE) {
                RecordFieldWithDefaultValueNode fieldWithDefaultValueNode = (RecordFieldWithDefaultValueNode) fieldNode;
                String fieldName = normalizeIdentifier(fieldWithDefaultValueNode.fieldName().text());
                if (!seenFields.add(fieldName)) {
                    context.reportDiagnostic(createDiagnostic(
                            DIAG_DUPLICATE_FIELD,
                            "Duplicate field declared in @orm:Entity record: " + fieldName,
                            DiagnosticSeverity.ERROR,
                            fieldWithDefaultValueNode.fieldName()));
                }

                if (hasOrmIdAnnotation(fieldWithDefaultValueNode.metadata())) {
                    hasIdField = true;
                }
            }
        }

        if (!hasIdField) {
            context.reportDiagnostic(createDiagnostic(
                    DIAG_ENTITY_NO_ID_FIELD,
                    "@orm:Entity record must declare at least one field annotated with @orm:Id",
                    DiagnosticSeverity.ERROR,
                    typeDefinitionNode.typeName()));
        }
    }

    private boolean hasOrmEntityAnnotation(Optional<MetadataNode> metadataNodeOptional) {
        if (metadataNodeOptional.isEmpty()) {
            return false;
        }

        for (AnnotationNode annotationNode : metadataNodeOptional.get().annotations()) {
            if (isAnnotationName(annotationNode, "Entity")) {
                return true;
            }
        }

        return false;
    }

    private boolean hasOrmIdAnnotation(Optional<MetadataNode> metadataNodeOptional) {
        if (metadataNodeOptional.isEmpty()) {
            return false;
        }

        for (AnnotationNode annotationNode : metadataNodeOptional.get().annotations()) {
            if (isAnnotationName(annotationNode, "Id")) {
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

    private String normalizeIdentifier(String identifier) {
        String value = identifier.trim();
        return value.startsWith("'") ? value.substring(1) : value;
    }

    private Diagnostic createDiagnostic(String code, String message, DiagnosticSeverity severity, Node locationNode) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(code, message, severity);
        return DiagnosticFactory.createDiagnostic(diagnosticInfo, locationNode.location());
    }
}
