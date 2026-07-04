allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Some plugins (e.g. onnxruntime 1.4.1) hardcode an older compileSdk in their
// own android/build.gradle, which fails AAR metadata checks against newer
// androidx transitive deps. Force every Android library module to compile
// against the same SDK as :app instead of waiting on upstream plugin releases.
// Registered before evaluationDependsOn below so afterEvaluate can still attach
// — once that triggers eager cross-project evaluation, it's too late to hook in.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
            compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
