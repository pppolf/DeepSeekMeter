// 纯逻辑核心模块（对齐 windows/src/DeepSeekMeter.Core 与 ios/DeepSeekMeterCore）：
// 业务逻辑零第三方依赖（org.json 为 Android 内置；网络用 HttpURLConnection）；
// 本地单测跑在 JVM 上（org.json 在 mockable android.jar 中有真实实现），无需设备。
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.deepseek.meter.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        // 不开启 returnDefaultValues：android.jar stub 方法应显式报错而非静默返回默认值
        unitTests.isReturnDefaultValues = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // 本地单测：JUnit 随 AGP/SDK 分发视同平台工具（MOBILE-PLAN.md 决策点 D5）
    testImplementation("junit:junit:4.13.2")
    // 测试期 org.json 真实现：Android 内置的 org.json 在 JVM 单测里是 stub（getJSONObject 返回 null），
    // 这里引入与系统内置同源的官方 jar 仅用于测试类路径；App 运行时仍用 Android 系统内置，零运行时依赖。
    testImplementation("org.json:json:20240303")
}
