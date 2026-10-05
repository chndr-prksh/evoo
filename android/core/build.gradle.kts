// Evoo's rules in plain Kotlin (no Android): fast to test, shared by the keyboard and the app.
plugins { id("org.jetbrains.kotlin.jvm") }

kotlin { jvmToolchain(17) }

dependencies { testImplementation(kotlin("test")) }

tasks.test {
    useJUnitPlatform()
    testLogging { showStandardStreams = true; events("failed") }
}
