document.getElementById('sendBtn').addEventListener('click', async () => {
    const status = document.getElementById('status');
    status.innerText = "正在发送...";

    // 1. 获取当前活动的标签页
    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    // 2. 在该页面执行脚本获取 HTML
    browser.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
            // 这里可以精细化，只抓取包含视频列表的容器节点
            const container = document.querySelector('.fav-video-list') || document.body;
            return container.innerHTML;
        }
    }).then(results => {
        const htmlContent = results[0].result;

        // 3. 将 HTML 发送到你的 PowerShell 监听端口
        fetch('http://localhost:58716/', {
            method: 'POST',
            mode: 'no-cors', // 简单起见使用 no-cors，或者在 PS 端配置好 CORS
            body: htmlContent
        })
        .then(() => {
            status.innerText = "发送成功！查看终端进度";
        })
        .catch(err => {
            status.innerText = "发送失败: " + err.message;
        });
    });
});