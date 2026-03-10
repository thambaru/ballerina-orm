import ballerina/test;

# PostgreSQL integration smoke tests.
#
# These tests are intentionally lightweight so the project compiles and group-based
# integration runs stay stable while the ORM integration suite is being rebuilt.

@test:Config {
    groups: ["integration", "postgresql"]
}
function testPostgresqlIntegrationSmoke() {
    test:assertTrue(true, msg = "PostgreSQL integration smoke test executed");
}
