# 扩展调试地址： about:debugging#/runtime/this-firefox

$ErrorActionPreference = 'stop'

$port = 58716
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

Write-Host "PowerShell API 已启动，监听端口 $port..." -ForegroundColor Cyan

try {
    while ($listener.IsListening) {
        
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        if ($request.HttpMethod -eq "POST") {

            # 处理跨域请求 (CORS)，允许来自扩展的请求
            $response.AddHeader("Access-Control-Allow-Origin", "*")
            
            # 读取 HTML 内容
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $html = $reader.ReadToEnd()
            
            # --- 在这里调用你的业务逻辑 ---
            Write-Host "收到来自 B 站收藏夹的 HTML，长度: $($html.Length)"

            $scriptPath = Join-Path $PSScriptRoot "bbdowner.ps1"
            Write-Host "检查脚本路径: $scriptPath"
            
            # 启动线程任务
            $job = Start-ThreadJob -ScriptBlock {
                param($scriptPath, $contentData)

                & {
                    try {

                        write-host "线程 $($MyInvocation.MyCommand.Name) 开始执行..." -ForegroundColor Yellow
        
                        . $scriptPath

                        # 当前工作目录
                        $targetDir = Split-Path -Parent $scriptPath


                        # 保存 mp3 的目录
                        $mp3Dir = Join-Path $targetDir -ChildPath "mp3"

                        $bbDownloader = [BbDownloader]::new()

                        # # 浏览器 f12 , 找到 html 节点，复制整体 html，程序从剪切板中的 html 中解析出链接
                        $urls = $bbDownloader.ParseUrlsFromContent($targetDir, $contentData)

                        # 开始下载链接中的视频并转换为 mp3
                        $bbDownloader.Download($urls, $mp3Dir)
                    }
                    catch {
                       write-error  "内部工作出错：$($_.Exception.Message)" 
                    }

                } *>&1 | Out-Host
        
            } -ArgumentList $scriptPath, $html -StreamingHost $Host

            Write-Host "已在线程 $($job.Id) 中启动下载任务..." -ForegroundColor Green

            $timeout = 10 # 最多等 10 次检查
            while ($timeout -gt 0) {
                Start-Sleep -Milliseconds 100                
                $timeout--

                $state = $job.State
                write-host "任务 $($job.Id) 状态: $state"

                if ($state -eq 'NotStarted') {
                    continue
                }

                break
            }

            Write-Host "任务 $($job.Id) 状态已切换为: $($job.State)" -ForegroundColor Green
        
            # 返回成功状态
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("OK")
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        $response.Close()
    }
}
finally {
    $listener.Stop()
}