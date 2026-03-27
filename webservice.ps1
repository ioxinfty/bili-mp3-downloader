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
            $jsonString = $reader.ReadToEnd()
            
            # --- 在这里调用你的业务逻辑 ---
            Write-Host "收到来自 B 站收藏夹的 HTML，长度: $($jsonString.Length)"

            $scriptPath = Join-Path $PSScriptRoot "bbdowner.ps1"
            Write-Host "检查脚本路径: $scriptPath"
            
            # 启动线程任务
            $job = Start-ThreadJob -ScriptBlock {
                param($scriptPath, $contentData)

                write-host '进入工作线程'

                & {
                    try {

                        write-host "线程 $($MyInvocation.MyCommand.Name) 开始执行..." -ForegroundColor Yellow
        
                        . $scriptPath

                        $data = $contentData | ConvertFrom-Json

                        # 提取参数
                        $type = $data.type         # 'collection' 或 'single_link'
                        $urls = $data.content   # HTML 或 URL
                        $mode = $data.mode         # 'tv', 'app', 'intl' 等
                        $isMp3 = $data.isMp3       # $true 或 $false
                        $singleOnly = $data.singleOnly # 是否仅下一首

                        # 当前工作目录
                        $targetDirName = "mp3"
                        if (-not $isMp3) {
                            $targetDirName = "video"
                        }
                        $workingDir = Split-Path -Parent $scriptPath
                        $taregtDir = Join-Path $workingDir -ChildPath $targetDirName

                        Write-Host "存储目录 $taregtDir"

                        $bbDownloader = [BbDownloader]::new()

                        if ($mode) {
                            $bbDownloader.SetMode($mode)
                        }

                        $bbDownloader.singleOnly = $singleOnly

                        if ($isMp3) {
                            $bbDownloader.DownloadMp3s($urls, $taregtDir)
                        }
                        else {
                            $bbDownloader.DownloadVideos($urls, $taregtDir)
                        }

                        write-host "下载完成"
                    }
                    catch {
                        write-error  "内部工作出错：$($_.Exception.Message)" 
                    }

                } *>&1 | Out-Host
        
            } -ArgumentList $scriptPath, $jsonString -StreamingHost $Host

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

                if ($state -eq 'Failed') {      
                    Write-Error "任务 $($job.Id) 运行出错：$($job.JobStateInfo.Reason.Message)"
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
catch {
    Write-Host "错误：$_" -ForegroundColor Red
    throw
}
finally {
    $listener.Stop()
}