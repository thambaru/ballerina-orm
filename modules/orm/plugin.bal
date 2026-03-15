# Compiler plugin scaffolding for schema analysis and model-aware code generation.

# Plugin diagnostic severity values.
public const PLUGIN_ERROR = "ERROR";
public const PLUGIN_WARNING = "WARNING";

# Severity type for plugin diagnostics.
public type PluginSeverity PLUGIN_ERROR|PLUGIN_WARNING;

# Compiler-plugin diagnostic payload.
#
# + code - Machine-readable diagnostic code.
# + message - Human-readable diagnostic description.
# + severity - Diagnostic severity: ERROR or WARNING.
# + model - Model name context, if applicable.
# + fieldName - Field name context, if applicable.
public type PluginDiagnostic record {| 
    string code;
    string message;
    PluginSeverity severity;
    string? model = ();
    string? fieldName = ();
|};

# Generated source payload for a type definition.
#
# + name - Name of the generated type.
# + content - Ballerina source code for the generated type.
public type GeneratedTypeSource record {| 
    string name;
    string content;
|};

# Generated source payload for a CRUD wrapper.
#
# + name - Name of the generated CRUD function.
# + content - Ballerina source code for the generated CRUD function.
public type GeneratedCrudSource record {| 
    string name;
    string content;
|};

# Generated artifacts for a single ORM model.
#
# + model - Model name these artifacts were generated for.
# + generatedTypes - List of generated type source payloads.
# + generatedCrud - List of generated CRUD source payloads.
public type ModelGeneration record {| 
    string model;
    GeneratedTypeSource[] generatedTypes;
    GeneratedCrudSource[] generatedCrud;
|};

# Output returned by the compiler-plugin execution pipeline.
#
# + schemaGraph - Parsed schema graph produced from the raw schema.
# + modelArtifacts - Map of model name to generated artifacts.
# + diagnostics - List of diagnostics emitted during analysis.
public type PluginExecution record {| 
    SchemaGraph schemaGraph;
    map<ModelGeneration> modelArtifacts;
    PluginDiagnostic[] diagnostics = [];
|};

# Orchestrates schema scan, analysis, and code generation.
public class CompilerPlugin {
    public function init() {
    }

    # Scan schema payload that was derived from `@orm:Entity` records.
    #
    # + rawSchema - The raw schema to scan.
    # + return - The scanned (possibly mutated) raw schema.
    public function scan(RawSchema rawSchema) returns RawSchema {
        return rawSchema;
    }

    # Execute plugin pipeline and return generated outputs and diagnostics.
    #
    # + rawSchema - Raw schema input derived from annotated record types.
    # + return - A PluginExecution with the schema graph, generated artifacts, and diagnostics.
    public function run(RawSchema rawSchema) returns PluginExecution|SchemaError {
        RawSchema scannedSchema = self.scan(rawSchema);
        SchemaGraph schemaGraph = check parseSchema(scannedSchema);
        PluginDiagnostic[] diagnostics = analyzeSchemaForPlugin(schemaGraph);
        map<ModelGeneration> modelArtifacts = generateModelArtifacts(schemaGraph);

        return {
            schemaGraph,
            modelArtifacts,
            diagnostics
        };
    }
}

# Convenience API that runs the default plugin implementation.
#
# + rawSchema - Raw schema input derived from annotated record types.
# + return - A PluginExecution with the schema graph, generated artifacts, and diagnostics.
public function executeCompilerPlugin(RawSchema rawSchema) returns PluginExecution|SchemaError {
    CompilerPlugin plugin = new;
    return plugin.run(rawSchema);
}

# Returns `true` if the plugin reported at least one error diagnostic.
#
# + execution - Plugin execution output to inspect.
# + return - `true` if at least one ERROR-severity diagnostic is present.
public function hasPluginErrors(PluginExecution execution) returns boolean {
    foreach PluginDiagnostic diagnostic in execution.diagnostics {
        if diagnostic.severity == PLUGIN_ERROR {
            return true;
        }
    }
    return false;
}

# Build an error diagnostic value.
#
# + code - Machine-readable diagnostic code.
# + message - Human-readable error description.
# + model - Model name context, if applicable.
# + fieldName - Field name context, if applicable.
# + return - A PluginDiagnostic with ERROR severity.
function pluginError(string code, string message, string? model = (), string? fieldName = ()) returns PluginDiagnostic {
    return {
        code,
        message,
        severity: PLUGIN_ERROR,
        model,
        fieldName
    };
}

# Build a warning diagnostic value.
#
# + code - Machine-readable diagnostic code.
# + message - Human-readable warning description.
# + model - Model name context, if applicable.
# + fieldName - Field name context, if applicable.
# + return - A PluginDiagnostic with WARNING severity.
function pluginWarning(string code, string message, string? model = (), string? fieldName = ()) returns PluginDiagnostic {
    return {
        code,
        message,
        severity: PLUGIN_WARNING,
        model,
        fieldName
    };
}
