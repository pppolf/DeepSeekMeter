# 发布 Windows x64 自包含版本并打包 ZIP（无需用户安装 .NET SDK）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File Scripts/publish-windows.ps1
param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root "windows\src\DeepSeekMeter\DeepSeekMeter.csproj"
$PublishDir = Join-Path $Root "windows\publish\win-x64"
$ZipDir = Join-Path $Root "windows\publish\DeepSeekMeter-win-x64"
$ZipFile = Join-Path $Root "windows\publish\DeepSeekMeter-win-x64.zip"

# 自包含单文件发布（WebView2Loader.dll 作为 native 依赖保留为单独文件）
dotnet publish $Project -c $Configuration -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $PublishDir

# 组装可直接解压运行的目录并打 ZIP
if (Test-Path $ZipDir) { Remove-Item $ZipDir -Recurse -Force }
New-Item -ItemType Directory -Path $ZipDir | Out-Null
Copy-Item -Path (Join-Path $PublishDir "*") -Destination $ZipDir -Recurse

if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
Compress-Archive -Path $ZipDir -DestinationPath $ZipFile

Write-Host "已生成 ZIP：$ZipFile"
