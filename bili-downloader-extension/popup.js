// 加载版本信息
document.addEventListener('DOMContentLoaded', async () => {
    const manifest = browser.runtime.getManifest();
    const versionInfo = document.getElementById('versionInfo');
    if (versionInfo) {
        versionInfo.textContent = `v${manifest.version}`;
    }
});


// 获取 UI 元素
const status = document.getElementById('status');
const downloadMode = document.getElementById('downloadMode');
const convertToMp3 = document.getElementById('convertToMp3');
const singlePageOnly = document.getElementById('singlePageOnly');

// 通用发送函数
async function sendDataToBackend(payload) {
    status.innerText = "正在发送...";
    
    // 合并公共参数（模式和是否转码）
    const data = {
        ...payload,
        mode: downloadMode.value,
        isMp3: convertToMp3.checked,
        singleOnly: singlePageOnly.checked,
        timestamp: new Date().getTime()
    };

    try {
        const response = await fetch('http://localhost:58716/', {
            method: 'POST',
            mode: 'no-cors', 
            headers: {
                'Content-Type': 'text/plain' // 这样不会发送 options 请求了
            },
            body: JSON.stringify(data)
        });
        status.innerText = "发送成功！查看终端进度";
    } catch (err) {        
        status.innerText = `发送失败: ${err.message}`;
        console.error("Fetch Error:", err);
    }
}

// 按钮 1：处理当前收藏夹 (发送 HTML 内容)
document.getElementById('sendHtmlBtn').addEventListener('click', async () => {
    
    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    const results = await browser.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
            const container = document.querySelector('.fav-list-main') || document.body;
            return container.outerHTML; // 使用 outerHTML 包含容器本身
        }
    });

    await sendDataToBackend({
        type: 'collection',
        content: results[0].result,
        url: tab.url
    });
});

// 按钮 2：处理当前链接 (仅发送 URL)
document.getElementById('SendLinkBtn').addEventListener('click', async () => {
    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    
    await sendDataToBackend({
        type: 'single_link',
        content: tab.url, // 对应你的需求：content 为当前链接
        url: tab.url
    });
});