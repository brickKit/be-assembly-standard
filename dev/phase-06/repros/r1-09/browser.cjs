// 用真实 Chromium 走一遍浏览器端登录：SPA（localhost:38001）→ Casdoor 登录页 → /callback → 浏览器内 fetch 换 token。
// 依赖本机已有的 playwright-core 与 Playwright 缓存的 Chromium（路径用环境变量传入，不安装任何东西）：
//   PW_CORE=<.../node_modules/playwright-core> PW_CHROMIUM=<.../chrome-linux64/chrome> node browser.cjs
const { chromium } = require(process.env.PW_CORE);
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.PW_CHROMIUM, headless: true });
  const page = await browser.newPage();
  const net = [];
  page.on("response", (r) => { if (r.url().startsWith("http://localhost:38000/") && !/\.(js|css|png|svg|ico|woff2?)/.test(r.url()))
    net.push(`${r.request().method()} ${r.status()} ${r.url().split("?")[0]}`); });
  page.on("console", (m) => { if (m.type() === "error") net.push("console.error " + m.text()); });
  await page.goto("http://localhost:38001/");
  await page.click("#login");
  await page.waitForURL(/localhost:38000\/login\/oauth\/authorize/, { timeout: 30000 });
  await page.waitForSelector("input#username", { timeout: 30000 });
  // Casdoor v4.1.0 登录页：用户名框 id=username，密码框 id=password
  await page.locator("input#username").fill("alice");
  await page.locator("input#password").fill("alice-pass-1");
  await page.locator("button[type=submit]").first().click();
  await page.waitForURL(/localhost:38001\/callback/, { timeout: 30000 });
  await page.waitForFunction(() => document.getElementById("out").textContent.includes("RESULT"), null, { timeout: 30000 });
  console.log("callback_url_params:", [...new URL(page.url()).searchParams.keys()].join(","));
  console.log(await page.textContent("#out"));
  console.log("--- casdoor requests seen by the browser ---\n" + net.join("\n"));
  await browser.close();
})().catch((e) => { console.error("BROWSER_SCRIPT_ERROR", e); process.exit(1); });
