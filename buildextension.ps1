# 构建扩展包 提交 https://addons.mozilla.org/zh-CN/developers/

$ErrorActionPreference = "Stop"

$extDir = Join-Path $PSScriptRoot "bili-downloader-extension"
$zipFile = Join-Path $PSScriptRoot "bili-downloader.zip"

# 如果已存在，先删除
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