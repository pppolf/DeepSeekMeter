// 顶层构建脚本：仅声明插件版本（子模块按需应用）
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("com.android.library") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    // Compose Compiler 插件（Kotlin 2.x 起必需；Compose 为 Android 官方 UI 工具链，非第三方业务依赖）
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
