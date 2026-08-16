// DeepSeekMeter Android 版（对齐 windows/ 平行实现模式；核心逻辑零第三方依赖）
// 仓库顺序：官方优先；阿里云镜像兜底（国内网络下官方源可能超时）
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
    }
}
rootProject.name = "DeepSeekMeterAndroid"
include(":core")
