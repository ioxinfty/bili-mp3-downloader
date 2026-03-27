# 从 bilibili 下载视频并转为 mp3
# 调用了 bbdown 命令, dotnet tool install -g bbdown, 最好登录一下
# 调用了 ffmpeg 命令, brew install ffmpeg

# 脚本参数定义
param(
    [Parameter(Mandatory = $false, HelpMessage = "下载类型：mp3 或 video，默认 mp3")]
    [ValidateSet("mp3", "video")]
    [string]$DownloadType = "mp3",

    [Parameter(Mandatory = $false, HelpMessage = "下载模式：tv (tv 端模式), app (app 端格式), intl (国际模式), 默认空为 pc 模式")]
    [ValidateSet("tv", "app", "intl")]
    [string]$DownloadMode = "",

    [Parameter(Mandatory = $false, HelpMessage = "要下载的单个链接, 如果未指定，则解析剪切板中的链接（假设为 html 源代码）")]
    [string]$Url,
    
    [Parameter(Mandatory = $false, HelpMessage = "是否显示帮助信息")]
    [switch]$Help
)


$ErrorActionPreference = 'stop' 
 
# 兼容一些低版本的 .net 工具
$env:DOTNET_ROLL_FORWARD = "LatestMajor"

class BbDownloader {

    # 从文本内容中解析出链接，下载链接中的视频并转换为 mp3，保存在桌面 mp3 文件夹中
    [void] DownloadFromContentToDesktop([string]$urlContent) { 
 
        [string[]]$urls = $urlContent -split "[\r\n]" | 
        ForEach-Object { $this.FormatUrl($_) } | 
        Where-Object { $_.Length -gt 0 } 
 
        # $urls 去重
        $urls = $urls | Select-Object -Unique
 
        $desktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
        $mp3Dir = Join-Path $desktop -ChildPath "mp3"

        $this.Download($urls, $mp3Dir)
    }
 
    # 格式化链接
    [string] FormatUrl([string]$url) { 
 
        # 正则取 https://www.bilibili.com/video/ 开头到空格为止
        $matche = [Regex]::Match($url, "https://www.bilibili.com/video/[^ ]+")   
        if (-not $matche.Success) {
            return ""
        }
 
        $url = $matche.Value
 
        # url 去掉 ?后的部分
        [System.UriBuilder]$uri = [System.UriBuilder]::new($url)
        $uri.Query = ""
 
        $url = "$($uri.Uri)"
 
        return $url
    }

    [string] GetVideoTitle([string]$url) {

        $bbdownArgs = @(
            "-info",
            $url
        )

        $output = & BBDown @bbdownArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host $output
            throw "bbdown 命令执行失败, 错误码 $LASTEXITCODE"
        }

        # 输出中找到 "标题: " 开头的行，取出标题
        $titleLine = $output | Where-Object { $_ -like "*视频标题:*" } | Select-Object -First 1

        if (-not $titleLine) {
            throw "未找到视频标题"
        }

        $pattern = "视频标题:\s*(?<title>.+)"
    
        $m = [Regex]::Match($titleLine, $pattern)
    
        if ($m.Success) {
            $title = $m.Groups["title"].Value.Trim()
        
            if (-not [string]::IsNullOrWhiteSpace($title)) {
                return $title
            }
        }

        throw "解析视频标题失败"
    }

    # 仅下载链接中的视频并转为 mp3，可能是一个视频，可能一个合集
    [void] DownloadMp3([string]$url, [string]$outputDir) { 

        # 创建输出目录
        New-Item $outputDir -ItemType Directory -Force | Out-Null

        Push-Location

        # 创建临时目录
        $tmpDir = Join-Path $([System.IO.Path]::GetTempPath()) -ChildPath $([System.IO.Path]::GetRandomFileName())
        New-Item -Path $tmpDir -ItemType Directory | Out-Null
        
        Set-Location $tmpDir
        Write-Host "切换临时目录 $tmpDir"

        try {
        
            $this.DownloadVideoFromUrl($url)

            [string[]] $mp4Files = $this.GetDownloadMp4Files($tmpDir)

            foreach ($mp4File in $mp4Files) {

                $mp3File = $this.ConvertVideoToMp3($mp4File)
                $this.MoveFileToOutputDir($mp3File, $outputDir)
            }
        }
        finally {
        
            Pop-Location
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        }

    }

    [void] SetMode($mode) {
        $this.downloadMode = "$mode".ToLower()
    }

    # 批量下载视频
    [void] DownloadVideos([string[]]$urls, [string]$outputDir) {

        # 批量下载视频
        $count = $urls | Measure-Object | Select-Object -ExpandProperty Count
        Write-Host "解析出 $count 个链接"

        foreach ($url in $urls) {            
            $this.DownloadVideo($url, $outputDir)
        }

    }

    # 仅下载链接中的视频， 可能是单个视频，可能是一个合集
    [void] DownloadVideo([string]$url, [string]$outputDir) { 

        # 创建输出目录
        New-Item $outputDir -ItemType Directory -Force | Out-Null

        # 创建临时目录
        $tmpDir = Join-Path $([System.IO.Path]::GetTempPath()) -ChildPath $([System.IO.Path]::GetRandomFileName())
        New-Item -Path $tmpDir -ItemType Directory | Out-Null

        Push-Location
        Write-Host "切换临时目录 $tmpDir"

        try {
        
            Write-Host "处理链接 $url"
            $this.DownloadVideoFromUrl($url)

            [string[]] $mp4Files = $this.GetDownloadMp4Files($tmpDir)

            foreach ($mp4File in $mp4Files) {
                $this.MoveFileToOutputDir($mp4File, $outputDir)
            }
        }
        finally {
        
            Pop-Location
            Remove-Item $tmpDir -Force -ErrorAction SilentlyContinue
        }
    }
 
    # 下载链接中的视频并转换为 mp3，保存在输出目录中
    [void] DownloadMp3s([string[]]$urls, [string]$outputDir) { 

        New-Item $outputDir -ItemType Directory -Force | Out-Null

        $count = $urls | Measure-Object | Select-Object -ExpandProperty Count
        Write-Host "解析出 $count 个链接"
 
        foreach ($url in $urls) { 
 
            Write-Host "处理链接 $url"
 
            $tmpDir = Join-Path $([System.IO.Path]::GetTempPath()) -ChildPath $([System.IO.Path]::GetRandomFileName())
            Write-Host "临时目录 $tmpDir"
 
            New-Item -Path $tmpDir -ItemType Directory | Out-Null
 
            $current = Get-Location
            Set-Location $tmpDir
 
            try {

                # 分析视频标题
                Set-Location $tmpDir # 因为下面的函数使用了当前目录
                $videoTitle = $this.GetVideoTitle($url)
                $mp3Name = $this.GetSafeFileName($videoTitle, "_")
                $mp3SaveFile = Join-Path $outputDir -ChildPath "$mp3Name.mp3"

                if (Test-Path -LiteralPath $mp3SaveFile) {
                    Write-Host "文件已存在，跳过: $mp3SaveFile" -ForegroundColor Yellow
                    continue
                }

                Set-Location $tmpDir # 因为下面的函数使用了当前目录
                $this.DownloadVideoFromUrl($url)

                $videoFile = $this.GetDownloadMp4File($tmpDir)
 
                $mp3File = $this.ConvertVideoToMp3($videoFile)
 
                Move-Item -LiteralPath $mp3File -Destination $mp3SaveFile -Force
            }
            finally {
 
                Set-Location $current

                Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

                # Start-Process 'open' $tmpDir
            }
 
        }
 
        Start-Process "open" -ArgumentList $outputDir
 
        Write-Host "处理完成"
    }
 
    # 移动文件到输出目录
    [void] MoveFileToOutputDir([string]$file, [string]$outputDir) {
 
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
 
        $fileName = [System.IO.Path]::GetFileName($file)
        $outputFile = Join-Path $outputDir -ChildPath $fileName
 
        write-host "移动文件 $file 到 $outputFile"
        Move-Item -LiteralPath $file -Destination $outputFile -Force

        if(-not $(test-path $outputFile)) {
            write-error "文件移动失败: $file"   
        }        
    }
 
    # 使用 ffmpeg 转换视频
    [string] ConvertVideoToMp3([string]$videoFile) {
      
 
        $mp3File = [System.IO.Path]::ChangeExtension($videoFile, ".mp3")
 
        # 构建 FFmpeg 参数数组（这种方式处理特殊字符路径最稳健）
        # 这里有推荐的一种转方法参数
        # https://blog.longwin.com.tw/2024/09/linux-ffmpeg-mp4-mp3-convert-2024/ 
        # ffmpeg -i video.mp4 -vn -acodec libmp3lame -ac 2 -ab 320k -ar 48000 audio.mp3
        $ffmpegArgs = @(
            "-hide_banner",          # 隐藏版本和编译信息
            "-loglevel", "error",    # 只显示错误，不输出过程日志
            # "-nostdin",              # 禁用标准输入，防止在脚本运行中卡死
            "-i", $videoFile,        # 输入文件
            "-vn",                   # 禁用视频流
            "-acodec", "libmp3lame", # 使用 mp3 编码器
            # "-qscale:a", "0",        # 最高质量 VBR
            "-ac", "2",              # 双声道
            "-ab", "320k",           # 320kbps
            "-ar", "48000",          # 48kHz
            $mp3File,                # 输出文件
            "-y"                     # 自动覆盖已存在文件
        )

        Write-Host "正在转换: $(Split-Path $videoFile -Leaf) ..." -ForegroundColor Cyan

        # 使用 & 直接调用，并捕获错误输出
        & ffmpeg @ffmpegArgs 2>&1 | Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg 转换失败，退出码: $LASTEXITCODE"
        }

        write-host "转换完成: $mp3File" -ForegroundColor Green
 
        return $mp3File
    }
 
    [string] GetSafeFileName([string]$fileName, [string]$replacement = "_") {
 
        # 1. 获取非法字符
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $pattern = "[{0}]" -f [regex]::Escape(-join $invalidChars)
 
        # 2. 替换非法字符
        $result = $fileName -replace $pattern, $replacement
 
        # 3. 移除不可见控制字符并修剪两端
        $result = $result -replace "[\x00-\x1f]", ""
 
        return $result.Trim()
    }

    # 获取下载的所有 mp4 文件
    [string[]] GetDownloadMp4Files([string]$dir) {
 
        $mp4Files = Get-ChildItem -Filter *.mp4 -Recurse 

        return $mp4Files
 
    }
 
    # 获取下载的 mp4 文件
    [string] GetDownloadMp4File([string]$dir) {
 
        $filePath = Get-ChildItem -Path $dir -Filter *.mp4 | Select-Object -First 1 | ForEach-Object { $_.FullName }
 
        if ($filePath -and $(Test-Path -LiteralPath $filePath)) {

            return $filePath 
        }
 
        Write-Host "可能有多首音乐"
 
        # 找到第一个 mp4 文件认为是需要的音乐
        $mp4File = Get-ChildItem -Filter *.mp4 -Recurse | Select-Object -First 1 | ForEach-Object { $_.FullName }
 
        if (-not $mp4File -and $(Test-Path -LiteralPath $mp4File)) {
            throw "没有找到视频文件"
        }            
 
        # 找到第一个文件夹认为是需要的音乐文件名
        $dirPath = Get-ChildItem -Directory | Select-Object -First 1 # | ForEach-Object { $_.Name }
        if (-not $dirPath -and $(Test-Path -LiteralPath $dirPath)) {
            throw "没有找到视频文件所在目录"
        }
 
        $dirName = [System.IO.Path]::GetFileName($dirPath)
        $dirRoot = [System.IO.Path]::GetDirectoryName($dirPath)
        $fileName = $this.GetSafeFileName($dirName, "-")
        $ext = [System.IO.Path]::GetExtension($mp4File)
 
        $filePath = Join-Path $dirRoot -ChildPath "$($fileName)$($ext)"
 
        [System.IO.File]::Copy($mp4File, $filePath)
 
        # Copy-Item $mp4File -Destination $filePath
        # Move-Item $mp4File -Destination $filePath
 
        if (-not $? -or (-not $filePath) -or (-not (Test-Path -LiteralPath $filePath))) {
            throw "复制视频文件失败"
        }
 
        return $filePath
    }

    # 下载的模式, tv (tv 端模式), app （app 端格式）, intl （国际片模式）
    [string]$downloadMode = ''

    # 是否只下载一首
    [bool]$singleOnly
 
    # 使用 bbdown 下载视频, 并得到 视频文件
    # 这里使用到了相对目录
    [void] DownloadVideoFromUrl([string]$url) {        

        $bbdownArgs = @()

        if ($this.downloadMode) {
            $bbdownArgs += "-$($this.downloadMode)"
        }

        if ($this.singleOnly) {
            
            # 解析出 url 中的 p 如果， 如果不存在则返回 1
            if ($url -match 'p=(?<page>\d+)') {
                $p = [int]$Matches['page']
            }
            else {
                $p = 1
            }

            $bbdownArgs += "-p $($p)"
        }

        $bbdownArgs += $url

        Write-Host "下载参数 $bbdownArgs"

        & BBDown @bbdownArgs 2>&1 | Out-Host 
 
        if ($LASTEXITCODE -ne 0) {
            throw "bbdown 命令执行失败, 错误码 $LASTEXITCODE"
        }
 
    }

    # 安装 AngleSharp 包
    [string] InstallAngleSharpPackage([string]$targetDir) {

        $dllPath = Join-Path $targetDir "AngleSharp.dll"
        
        if (Test-Path -LiteralPath $dllPath) {
            Write-Host "AngleSharp.dll 已存在于目标目录"            
            return $dllPath
        }

        Write-Host "下载 AngleSharp 包..."
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        try {
            $nupkgUrl = "https://files.443disk.xyz/NugetPackages/anglesharp.1.4.0.nupkg"
            $nupkgPath = Join-Path $tempDir "anglesharp.1.4.0.nupkg"

            Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath -UseBasicParsing
            if (-not (Test-Path -LiteralPath $nupkgPath)) { throw "下载失败: $nupkgPath" }

            Write-Host "解压缩包..."
            $extractDir = Join-Path $tempDir "extract"
            Expand-Archive -Path $nupkgPath -DestinationPath $extractDir -Force

            Write-Host "查找 AngleSharp.dll..."
            $dllSource = Join-Path $extractDir "lib/netstandard2.0/AngleSharp.dll"
            if (-not (Test-Path -LiteralPath $dllSource)) {
                throw "未找到 AngleSharp.dll: $dllSource"
            }

            Copy-Item -Path $dllSource -Destination $dllPath -Force
            Write-Host "AngleSharp.dll 已复制到目标目录"
            
            return $dllPath
        }
        finally {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }

    [string[]] ParseUrlsFromContent($targetDir, $html) {

        $dllPath = $this.InstallAngleSharpPackage($targetDir)

        Add-Type -Path $dllPath

        $parserType = "AngleSharp.Html.Parser.HtmlParser"
        $parser = New-Object $parserType
        
        $doc = $parser.ParseDocument($html)
        $els = $doc.QuerySelectorAll('a[href^="https://www.bilibili.com/video/"]')
        $urls = $els | ForEach-Object { $_.GetAttribute('href') } | Select-Object -Unique

        return $urls
    }

    # 从剪切板中解析出链接
    [string[]] ParseUrlsFromClipboard($targetDir) { 
 
        $html = Get-Clipboard -Raw

        return $this.ParseUrlsFromContent($targetDir, $html)
    }
}


# 主程序入口
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.InvocationName -ne '&') {
 
    # 到这里是直接调用
    
    # 显示帮助信息
    function Show-Help {
        Write-Host "B站视频下载工具" -ForegroundColor Green
        Write-Host "----------------------------------------"
        Write-Host "用法：bbdowner.ps1 [-DownloadType <mp3|video>] [-Url <链接>] [-Help]"
        Write-Host ""
        Write-Host "参数说明："
        Write-Host "-DownloadType    指定下载类型：mp3（默认）或 video"
        Write-Host "-Url             指定要下载的单个链接或是从剪切板中解析链接"
        Write-Host "-Help            显示此帮助信息"
        Write-Host ""
        Write-Host "示例："
        Write-Host 'bbdowner.ps1 -DownloadType mp3 -Url "https://www.bilibili.com/video/BV1xx411c7XW"'
        Write-Host 'bbdowner.ps1 -DownloadType video -Url "https://www.bilibili.com/video/BV1xx411c7XW"'
        Write-Host ""
        Write-Host "不指定参数时，将从剪贴板解析链接并下载为 mp3"
    }

    # 显示帮助信息
    if ($Help) {
        Show-Help
        return
    }

    if (-not $DownloadType) {
        $DownloadType = "mp3"
    }

    $bbDownloader = [BbDownloader]::new()
    
    # 下载模式
    $bbDownloader.SetMode($DownloadMode)

    # 输出路径
    $targetDir = $PSScriptRoot
    
    # 根据下载类型确定输出目录
    $outputDir = Join-Path $targetDir -ChildPath $DownloadType
    
    # 确保输出目录存在
    New-Item $outputDir -ItemType Directory -Force | Out-Null
    
    # 处理下载链接
    if ($Url) {
        # 处理单个链接
        Write-Host "处理链接：$Url" -ForegroundColor Cyan
        
        if ($DownloadType -eq "mp3") {
            $bbDownloader.DownloadMp3($Url, $outputDir)
        }
        else {
            $bbDownloader.DownloadVideo($Url, $outputDir)
        }
        
        Start-Process "open" -ArgumentList $outputDir
        Write-Host "处理完成"
    }
    else {
        # 从剪贴板解析链接（默认行为）
        $Content = Get-Clipboard -Raw
        
        # 浏览器 f12 , 找到 html 节点，复制整体 html，程序从剪切板中的 html 中解析出链接
        $urls = $bbDownloader.ParseUrlsFromContent($targetDir, $Content)
        
        if ($DownloadType -eq "mp3") {
            $bbDownloader.DownloadMp3s($urls, $outputDir)
        }
        else {
            $bbDownloader.DownloadVideos($urls, $outputDir)

            Start-Process "open" -ArgumentList $outputDir
            Write-Host "处理完成"
        }
    }
}

