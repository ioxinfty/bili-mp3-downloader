# bilibili mp3 下载工具

为了方便从 b 站的收藏夹中下载视频并转为 mp3 的工具

## 使用

1. 安装 `pwsh`
1. 安装 `pwsh` 模块 `Install-Module -Name ThreadJob -Scope CurrentUser`
1. 安装 `bbdown` `dotnet tool install -g bbdown`
1. 登录 `bbdown login`
1. 安装 `ffmpeg` `brew install ffmpeg`
1. 安装 `firefox` 扩展 `bili-downloader-extension` 
1. 执行 `webservice.ps1`
1. 点击 `firefox` 扩展 `Bili MP3 Downloader`, 点击 `处理当前页面` 按钮
1. 在 `webservice.ps1` 运行窗口中查看下载日志
1. 处理完成的 `mp3` 保存于 `webservice.ps1` 所在目录的 `mp3` 目录中


## 更新

目前手工打包发布, 未公开发布

1. 更新 `manifest.json` 版本号
1. 调用 `buildextension.ps1` 打包 `bili-downloader.zip`
1. 上传 `bili-downloader.zip` 审核 
1. 审核完成, 下载 `xpi` 文件，保存为 `bili-mp3-downloader.xpi`
1. github 上新建 `release` 并上传 `bili-mp3-downloader.xpi`
1. 得到新的 `bili-mp3-downloader.xpi` 下载地址
1. 将下载地址更新到 `updates.json`
1. 清理 `bili-downloader.zip` 与 `bili-mp3-downloader.xpi`
1. 签入代码
1. 用户等待扩展更新=生效后更新扩展