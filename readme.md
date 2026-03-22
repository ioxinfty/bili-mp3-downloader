# bilibili mp3 下载工具

为了方便从 b 站的收藏夹中下载视频并转为 mp3 的工具

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
