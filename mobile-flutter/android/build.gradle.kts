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
// Selaraskan compileSdk SEMUA modul (termasuk plugin) ke 36 (terpasang).
// Beberapa plugin (mis. flutter_secure_storage 11) menuntut compileSdk 37 yang
// hanya tersedia sebagai preview (android-37.0) → error "hash string 'android-37'".
// WAJIB didaftarkan SEBELUM evaluationDependsOn(":app") agar afterEvaluate tak
// terlambat (":app" keburu dievaluasi → "project is already evaluated").
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
