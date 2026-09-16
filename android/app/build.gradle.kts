// Trecho relevante de segurança/build. O restante é o template padrão do Flutter.
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Os plugins do Firebase só entram quando existe google-services.json.
//
// Sem isto, clonar o repositório e rodar `flutter run` falha no Gradle antes de
// qualquer linha de Dart — inclusive no modo demo, que nem usa Firebase. E como
// google-services.json é por flavor e gerado pelo `flutterfire configure`, ele
// não está versionado até o projeto Firebase existir.
//
// Assim que o arquivo aparece, os plugins passam a ser aplicados sozinhos.
val hasFirebaseConfig = file("google-services.json").exists() ||
    fileTree("src").matching { include("**/google-services.json") }.files.isNotEmpty()

if (hasFirebaseConfig) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.lifecycle(
        "Shield Ack: google-services.json ausente — Firebase desativado neste build. " +
        "Rode `flutterfire configure` antes de publicar."
    )
}

android {
    namespace = "br.com.shieldack.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // Java e Kotlin precisam do mesmo alvo de JVM, senao o Gradle aborta.
    compileOptions {
        // flutter_local_notifications exige desugaring da core library.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.shieldack.app"
        // 24 = Android 7. Abaixo disso o Keystore e o TLS moderno ficam frágeis
        // e o Play Integrity não é confiável.
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Credenciais vêm do ambiente do CI. NUNCA do repositório.
            storeFile = System.getenv("ANDROID_KEYSTORE_PATH")?.let { file(it) }
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true      // R8: ofusca e remove código morto
            isShrinkResources = true    // remove recursos não referenciados
            isDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".dev"
        }
    }

    // Flavors = projetos Firebase distintos. Misturar dev e prod no mesmo projeto
    // é como se apaga dado de produção num teste de carga.
    flavorDimensions += "env"
    productFlavors {
        create("dev")     { dimension = "env"; applicationIdSuffix = ".dev" }
        create("staging") { dimension = "env"; applicationIdSuffix = ".stg" }
        create("prod")    { dimension = "env" }
    }

    packaging {
        resources.excludes += setOf("META-INF/*.version", "**/*.kotlin_metadata")
    }
}

// Alinha o Kotlin ao mesmo alvo de JVM do Java acima (compileOptions).
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
