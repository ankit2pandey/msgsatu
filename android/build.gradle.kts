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
// telephony_sms 0.0.4 pins its Android library to API 33, while its
// AndroidX dependencies require API 34 or newer. Register the override before
// evaluationDependsOn can cause plugin projects to be evaluated.
subprojects {
    if (name == "telephony_sms") {
        afterEvaluate {
            val androidExtension = extensions.findByName("android")
                ?: error("Android extension not found for telephony_sms")
            val compileSdkSetter = androidExtension.javaClass.methods.firstOrNull {
                it.name == "setCompileSdkVersion" &&
                    it.parameterCount == 1 &&
                    it.parameterTypes[0] == Integer.TYPE
            } ?: error("Could not override telephony_sms compileSdkVersion")

            compileSdkSetter.invoke(androidExtension, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
