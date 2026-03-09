import ballerina/test;

@test:Config {}
function testParseMysqlConnectionUrl() {
    ParsedConnectionUrl parsed = checkpanic parseConnectionUrl("mysql://alice:secret@db.local:3307/app_db?ssl=true&connectTimeout=10");

    test:assertEquals(parsed.provider, MYSQL);
    test:assertEquals(parsed.host, "db.local");
    test:assertEquals(parsed.port, 3307);
    test:assertEquals(parsed.user, "alice");
    test:assertEquals(parsed.password, "secret");
    test:assertEquals(parsed.database, "app_db");
    test:assertEquals(parsed.query.get("ssl"), "true");
    test:assertEquals(parsed.query.get("connectTimeout"), "10");
}

@test:Config {}
function testParsePostgresqlConnectionUrlWithDefaults() {
    ParsedConnectionUrl parsed = checkpanic parseConnectionUrl("postgresql://postgres@localhost/sampledb");

    test:assertEquals(parsed.provider, POSTGRESQL);
    test:assertEquals(parsed.host, "localhost");
    test:assertEquals(parsed.port, DEFAULT_POSTGRESQL_PORT);
    test:assertEquals(parsed.user, "postgres");
    test:assertEquals(parsed.database, "sampledb");
}

@test:Config {}
function testNormalizeClientConfigWithUrlAndOverrides() {
    NormalizedClientConfig normalized = checkpanic normalizeClientConfig({
        url: "postgresql://postgres@localhost:5432/app",
        user: "app_user",
        password: "pw",
        port: 5544
    });

    test:assertEquals(normalized.provider, POSTGRESQL);
    test:assertEquals(normalized.host, "localhost");
    test:assertEquals(normalized.port, 5544);
    test:assertEquals(normalized.user, "app_user");
    test:assertEquals(normalized.password, "pw");
    test:assertEquals(normalized.database, "app");
}

@test:Config {}
function testNormalizeClientConfigProviderMismatch() {
    NormalizedClientConfig|ClientError normalized = normalizeClientConfig({
        provider: MYSQL,
        url: "postgresql://postgres@localhost:5432/app"
    });

    test:assertTrue(normalized is ClientError);
    if normalized is ClientError {
        ClientErrorDetail detail = normalized.detail();
        test:assertEquals(detail.code, "CLIENT_PROVIDER_MISMATCH");
    }
}
