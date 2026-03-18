import ballerina/test;

# Root module smoke test to verify the package compiles correctly.
@test:Config {}
function testRootModuleCompiles() {
    test:assertTrue(true, msg = "Root module smoke test executed");
}
