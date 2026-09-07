import {test, expect} from '@playwright/test';

test('create, complete, filter and reopen a task', async ({page}, testInfo) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await expect(page.getByRole('heading', {name: 'Make something real.'})).toBeVisible();
  await page.getByLabel('New experiment').fill('Reopen the orbital scene');
  await page.getByRole('button', {name: 'Add experiment'}).click();
  const item = page.getByRole('checkbox', {name: 'Reopen the orbital scene'});
  await item.check();
  await page.getByRole('button', {name: 'Completed', exact: true}).click();
  await expect(item).toBeChecked();
  await page.reload();
  await expect(item).toBeChecked();
  await page.getByRole('button', {name: 'Active', exact: true}).click();
  await expect(item).toHaveCount(0);
  await page.getByRole('button', {name: 'All', exact: true}).click();
  await expect(item).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  expect(errors).toEqual([]);
  await page.screenshot({path: testInfo.outputPath('completed-flow.png'), fullPage: true});
});

test('keyboard entry and empty filter are usable', async ({page}) => {
  await page.goto('/');
  await page.getByRole('button', {name: 'Completed', exact: true}).click();
  await expect(page.getByText('Nothing here yet.')).toBeVisible();
  await page.getByLabel('New experiment').focus();
  await page.keyboard.type('Keyboard-driven experiment');
  await page.keyboard.press('Enter');
  await expect(page.getByRole('checkbox', {name: 'Keyboard-driven experiment'})).toBeVisible();
});
