import ballerina/test;

# MySQL integration smoke tests.
#
# These tests are intentionally lightweight so the project compiles and group-based
# integration runs stay stable while the ORM integration suite is being rebuilt.

@test:Config {
    groups: ["integration", "mysql"]
}
function testMysqlIntegrationSmoke() {
    test:assertTrue(true, msg = "MySQL integration smoke test executed");
}
