// Root-level build.gradle.kts

plugins {
    id("com.android.application") apply false
    id("com.google.gms.google-services") apply false
    id("org.jetbrains.kotlin.android") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Optional: Custom build directory (can remove if not needed)
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

// ✅ Global version values used in app module
extra.apply {
    set("compileSdkVersion", 34)
    set("minSdkVersion", 21)
    set("targetSdkVersion", 34)
}
