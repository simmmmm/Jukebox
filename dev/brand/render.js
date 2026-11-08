// An HTML page to a PNG, by Chromium: how the brand's SVGs (icon.py,
// station.py) become pictures. Needs playwright (`npm i playwright`,
// `npx playwright install chromium`).
//
//   node render.js in.html out.png width height [scale]
const { chromium } = require('playwright');
(async () => {
  const [,, inp, out, w, h, s] = process.argv;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: +(s || 1) });
  await page.goto('file://' + require('path').resolve(inp));
  await page.waitForTimeout(150);
  await page.screenshot({ path: out, omitBackground: false });
  await browser.close();
})();
