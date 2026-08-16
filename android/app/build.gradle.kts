// App 模块（A3）：Compose UI 薄壳，业务逻辑全部来自 :core。
// Compose/Material3 为 Google 官方 UI 工具链（红线 11 不视为第三方业务依赖）；
// WebView 登录用平台 android.webkit（零额外依赖）。
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.deepseek.meter.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.deepseek.meter.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.3.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // GitHub Release 直装 APK 用 debug 签名（与 macOS 版 ad-hoc 签名理念一致）：
            // 任何人均可构建/重签，签名仅保证可安装，不构成信任背书。
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
        // QA 测试通知入口依赖 BuildConfig.DEBUG 门控（仅 debug 构建显示，release 自动剔除）
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))

    // Compose 官方工具链（BOM 统一版本）
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")

    // 后台刷新调度（D6 已决策，见 MOBILE-PLAN.md / Issue #11）：androidx 官方后台调度库，
    // 仅用于 :app 层低余额后台刷新；:core 保持零 AndroidX 依赖。
    // 版本选择依据：Issue #11 / D6 要求 ≥ 2.8.0（ExistingPeriodicWorkPolicy.UPDATE 语义）；
    // 2.10.1 为稳定版，其 minSdk 23 < 本项目 minSdk 26，兼容。
    implementation("androidx.work:work-runtime:2.10.1")
}
