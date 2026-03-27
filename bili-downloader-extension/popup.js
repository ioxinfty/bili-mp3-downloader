// 加载版本信息
document.addEventListener("DOMContentLoaded", async () => {
    const manifest = browser.runtime.getManifest();
    const versionInfo = document.getElementById("versionInfo");
    if (versionInfo) {
        versionInfo.textContent = `v${manifest.version}`;
    }
});

// 获取 UI 元素
const status = document.getElementById("status");
const downloadMode = document.getElementById("downloadMode");
const convertToMp3 = document.getElementById("convertToMp3");
const singlePageOnly = document.getElementById("singlePageOnly");

// 通用发送函数
async function sendDataToBackend(payload) {
    status.innerText = "正在发送...";

    // 合并公共参数（模式和是否转码）
    const data = {
        ...payload,
        mode: downloadMode.value,
        isMp3: convertToMp3.checked,
        singleOnly: singlePageOnly.checked,
        timestamp: new Date().getTime(),
    };

    try {
        const response = await fetch("http://localhost:58716/", {
            method: "POST",
            mode: "no-cors",
            headers: {
                "Content-Type": "text/plain", // 这样不会发送 options 请求了
            },
            body: JSON.stringify(data),
        });
        status.innerText = "发送成功！查看终端进度";
    } catch (err) {
        status.innerText = `发送失败: ${err.message}`;
        console.error("Fetch Error:", err);
    }
}

// 设置 status 中的信息
function setStatusError(text) {
    if (text) {
        status.innerText = text;
        status.className = "mt-3 small text-danger fw-bold";
    }
    else {
        status.innerText = "";
        status.className = "mt-3 small text-muted";
    }

}

// 解析出收藏夹中的链接
async function parseFavListPage() {
    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    const results = await browser.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
            const container =
                document.querySelector(".fav-list-main") || document.body;

            // 提取所有视频链接
            const links = Array.from(
                container.querySelectorAll(
                    'a[href^="//www.bilibili.com/video/"], a[href^="https://www.bilibili.com/video/"]',
                ),
            );

            // 清洗 URL：去重、补全协议、去除冗余参数
            const uniqueUrls = [
                ...new Set(
                    links.map((a) => {
                        let href = a.href;
                        // 补全协议（如果是 // 开头）
                        if (href.startsWith("//")) href = "https:" + href;

                        try {
                            const urlObj = new URL(href);
                            // 只保留协议、域名、路径（去掉 spm_id 等追踪参数）
                            // 如果有选集参数 p，可以根据需要决定是否保留。这里默认保留 p
                            const p = urlObj.searchParams.get("p");
                            let cleanUrl = `${urlObj.origin}${urlObj.pathname}`;
                            return p ? `${cleanUrl}?p=${p}` : cleanUrl;
                        } catch (e) {
                            return href;
                        }
                    }),
                ),
            ];

            return uniqueUrls;
        },
    });

    const videoUrls = results[0].result;
    console.log("videoUrls:", videoUrls);

    return videoUrls;
}

// 解析出页面中是否有 //div[@data-key] 链接
async function hasDataKeyUrls() {

    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    const results = await browser.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => !!document.querySelector('div[data-key]'), 
    });

    return results[0].result;
}

// 解析出页面中的链接 //div[@data-key], 并合并成 https://www.bilibili.com/video/BV1gvF4z5E9H
async function parseDataKeyUrls() {

    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    const results = await browser.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
            const container = document.body;

            // 1. 获取所有带 data-key 的 div
            const elements = Array.from(container.querySelectorAll('div[data-key]'));

            // 2. 提取、过滤并转换
            const urlList = elements
                .map(el => el.dataset.key) // 使用 dataset 访问 data-key
                .filter(key => key && key.startsWith("BV")) // 过滤掉不符合条件的
                .map(key => `https://www.bilibili.com/video/${key}`); // 拼接

            // 3. 利用 Set 去重并转回数组
            return [...new Set(urlList)];
        },
    });

    return results[0].result;
}

// 按钮 1：处理当前收藏夹 (发送 HTML 内容)
document.getElementById("sendBut").addEventListener("click", async () => {
    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    setStatusError()

    const isBili = /^(https?:\/\/)?([a-z0-9-]+\.)?bilibili\.com(\/.*)?$/i.test(
        tab.url,
    );
    if (!isBili) {
        setStatusError("当前页面不是 Bilibili 链接")
        return;
    }

    // 收藏夹页面处理
    const isFavListPage = /^https:\/\/space\.bilibili\.com\/\d+\/favlist/i.test(
        tab.url,
    );

    console.log("isFavListPage:", isFavListPage);

    if (isFavListPage) {

        console.log("处理收藏夹页面")

        const urls = await parseFavListPage();

        await sendDataToBackend({
            type: "collection",
            content: urls,
            url: tab.url,
        });

        return;
    }

    {
        const urls = await parseDataKeyUrls();

        console.log("urls:", urls);

        if (urls.length > 0) {
            // 合集
            if (singlePageOnly.checked) {

                console.log("处理合集中的单曲")

                await sendDataToBackend({
                    type: "collection",
                    content: [tab.url,],
                    url: tab.url,
                });
            }
            else {

                console.log("处理合集中的单曲")

                await sendDataToBackend({
                    type: "collection",
                    content: urls,
                    url: tab.url,
                });
            }

            return;
        }
    }

    var url = tab.url
    if(!singlePageOnly.checked){
        // 去掉 url 中可能的 p 参数
        url = url.replace(/p=\d+/, "");
    }

    console.log(`处理当前链接: ${url}`)

    await sendDataToBackend({
        type: "collection",
        content: [url,],
        url: tab.url,
    });

});

