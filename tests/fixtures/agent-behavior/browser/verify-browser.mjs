import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const root = path.resolve(process.argv[2]);
const require = createRequire(path.join(root, 'package.json'));
const {chromium} = require('@playwright/test');
const browser = await chromium.launch({headless: true});
const results = [];
try {
  for (const [label, width, height, reducedMotion] of [
    ['desktop', 1440, 900, 'no-preference'], ['mobile-reduced', 390, 844, 'reduce'],
  ]) {
    const page = await browser.newPage({viewport: {width, height}, reducedMotion});
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    await page.goto(pathToFileURL(path.join(root, 'index.html')).href);
    const toggle = page.getByRole('button', {name: /pause|play/i});
    const speed = page.getByRole('slider', {name: /speed/i});
    await toggle.waitFor();
    const before = await toggle.getAttribute('aria-pressed');
    if (!['true', 'false'].includes(before)) throw Error('Pause state is not exposed');
    if (reducedMotion === 'reduce' && before !== 'true') throw Error('Reduced motion did not start paused');
    await toggle.focus();
    await page.keyboard.press('Space');
    if (await toggle.getAttribute('aria-pressed') === before) throw Error('Keyboard toggle did not change state');
    await speed.focus();
    await page.keyboard.press('Home');
    const minimum = await speed.inputValue();
    await page.keyboard.press('End');
    if (await speed.inputValue() === minimum) throw Error('Speed slider did not respond to keyboard');
    await page.getByRole('button', {name: /reset/i}).click();
    if (await speed.inputValue() !== '1') throw Error('Reset did not restore speed');
    if (await toggle.getAttribute('aria-pressed') !== 'true') throw Error('Reset did not pause');
    if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) throw Error('Horizontal overflow');
    if (errors.length) throw Error(errors.join('\n'));
    fs.mkdirSync(path.join(root, 'evidence'), {recursive: true});
    await page.screenshot({path: path.join(root, 'evidence', `verifier-${label}.png`), fullPage: true});
    results.push({name: `${label}: keyboard, reset, speed, layout and runtime`, passed: true});
    await page.close();
  }
  console.log(JSON.stringify({checks: results, manual_review: ['Inspect both screenshots for aesthetics and readability; verify motion quality in a visible browser. Functional checks alone do not establish visual quality.']}, null, 2));
} finally {
  await browser.close();
}
