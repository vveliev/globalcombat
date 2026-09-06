// Re-runnable browser proof that the boutique layer's shell font-body/
// font-heading wiring and the Google Fonts @import order both actually
// take effect. Requires a running `mix phx.server` on PORT (default 11400)
// and Playwright's Chromium available locally — set
// CHROME_PATH/LD_LIBRARY_PATH if the sandboxed executable needs them (see
// liveview/AGENTS.md or the project's sandbox notes for the exact paths).
//
// Usage: node scripts/verify_theme_fonts.js [http://127.0.0.1:11400]
const { chromium } = require("playwright");

const BASE_URL = process.argv[2] || "http://127.0.0.1:11400";
const THEMES = ["industry-light", "industry-dark"];

async function checkTheme(browser, theme) {
  const page = await browser.newPage();
  await page.goto(`${BASE_URL}/design`, { waitUntil: "networkidle" });
  await page.evaluate((t) => document.documentElement.setAttribute("data-theme", t), theme);
  await page.evaluate(() => document.fonts.ready);

  const result = await page.evaluate(() => {
    // The GameLayout shell root — not <body> itself — carries `body-text`;
    // its computed font-family/size/line-height is what every page's copy
    // actually inherits.
    const shellRoot = document.querySelector('[class*="body-text"]');
    // Inherited descendant, proving the cascade actually reaches page copy,
    // not just the shell root itself.
    const bodyCopy = document.querySelector("p");
    // DesignSmokeLive's Card header ("design-boutique renders here") is
    // rendered as the page's only <h1> via Card's font-heading class.
    const cardHeading = document.querySelector("h1");
    // The status-strip turn number uses the heading-3 utility.
    const turnNumber = document.querySelector(".heading-3.tabular-nums");

    const cs = (el) => (el ? getComputedStyle(el) : null);
    const shellStyle = cs(shellRoot);
    const bodyCopyStyle = cs(bodyCopy);
    const headingStyle = cs(cardHeading);
    const turnStyle = cs(turnNumber);

    return {
      dataTheme: document.documentElement.getAttribute("data-theme"),
      shellRoot: shellStyle && {
        fontFamily: shellStyle.fontFamily,
        fontSize: shellStyle.fontSize,
        lineHeight: shellStyle.lineHeight,
      },
      bodyCopy: bodyCopyStyle && {
        text: bodyCopy.textContent.trim().slice(0, 40),
        fontFamily: bodyCopyStyle.fontFamily,
      },
      heading: headingStyle && {
        text: cardHeading.textContent.trim(),
        fontFamily: headingStyle.fontFamily,
        fontWeight: headingStyle.fontWeight,
        fontSize: headingStyle.fontSize,
      },
      turnNumber: turnStyle && {
        text: turnNumber.textContent.trim(),
        fontFamily: turnStyle.fontFamily,
        fontWeight: turnStyle.fontWeight,
        fontSize: turnStyle.fontSize,
        fontVariantNumeric: turnStyle.fontVariantNumeric,
      },
      fontsLoaded: {
        "400 16px Barlow": document.fonts.check("400 16px Barlow"),
        "16px Barlow": document.fonts.check("16px Barlow"),
        "600 16px Barlow Condensed": document.fonts.check('600 16px "Barlow Condensed"'),
        "16px Barlow Condensed": document.fonts.check('16px "Barlow Condensed"'),
      },
      loadedFontFaces: Array.from(document.fonts)
        .filter((f) => f.status === "loaded")
        .map((f) => `${f.family} ${f.weight}`),
    };
  });

  await page.close();
  return result;
}

async function main() {
  const executablePath = process.env.CHROME_PATH || undefined;
  const browser = await chromium.launch({
    executablePath,
    args: ["--no-sandbox", "--disable-gpu"],
  });

  try {
    for (const theme of THEMES) {
      const result = await checkTheme(browser, theme);
      console.log(`\n=== ${theme} ===`);
      console.log(JSON.stringify(result, null, 2));
    }
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
