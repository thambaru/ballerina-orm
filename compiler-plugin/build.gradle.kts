plugins {
    id("java-library")
}

group = "io.ballerina.orm"
version = "0.1.0"

repositories {
    mavenCentral()
    // Ballerina artifacts are typically published to Maven Central
    // If unavailable, point to your local Ballerina distribution
}

dependencies {
    // Compiler plugin API (provided by Ballerina runtime)
    compileOnly("org.ballerinalang:ballerina-lang:2201.13.1")
    compileOnly("org.ballerinalang:ballerina-tools-api:2201.13.1")
   
    // Dependency on the Ballerina ORM package (once published)
    // implementation("io.ballerina.orm:bal_orm:0.1.0")
   
    testImplementation("org.junit.jupiter:junit-jupiter:5.9.3")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

tasks.withType<Test> {
    useJUnitPlatform()
}
