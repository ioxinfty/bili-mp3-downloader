# 构建扩展包 提交 https://addons.mozilla.org/zh-CN/developers/

$ErrorActionPreference = "Stop"

$workingDir = $PSScriptRoot
$extDir = Join-Path $workingDir "bili-downloader-extension"
$zipFile = Join-Path $workingDir "bili-downloader.zip"

$manifestPath = Join-Path $extDir "manifest.json"
$updatesPath = Join-Path $workingDir "updates.json"

# --- 1. 读取 Manifest 中的版本号 ---
if (-not (Test-Path $manifestPath)) { Throw "找不到 manifest.json 文件！" }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$currentVersion = $manifest.version
$addonId = $manifest.browser_specific_settings.gecko.id
$updateUrl = $manifest.browser_specific_settings.gecko.update_url
$updateLink = $updateUrl -replace "updates.json", "bili-mp3-downloader.xpi"

# --- 2. 更新 updates.json 中的版本号和链接 ---
$updateDict = @{
    "addons" = @{
        $addonId = @{
            "updates_url" = $updateLink
            "update_link" = $currentVersion
        }
    }
}
$updateDict | ConvertTo-Json -Depth 10 | Out-File $updatesPath -Encoding UTF8
Write-Host "已更新 updates.json 文件" -ForegroundColor Green

# --- 3. 打包扩展 ---
if (Test-Path $zipFile) { Remove-Item $zipFile }

Push-Location $extDir

try {
    # -r: 递归
    # -q: 安静模式
    # -x: 排除模式 (注意：排除路径通常需要匹配文件夹下的内容)
    zip -r -q $zipFile . -x "*.DS_Store" -x ".git/*" -x ".git"
    Write-Host "扩展已通过系统 zip 成功打包至: $zipFile" -ForegroundColor Green
}
finally {
    Pop-Location
}