import {expect, test} from '@playwright/test';

test.beforeEach(async ({page}) => {
  await page.addInitScript(() => {
    window.__webmcpTools = [];
    window.__webmcpAbortCount = 0;
    window.__modelContext = {
      registerTool: async (tool, options) => {
        window.__webmcpTools.push(tool);
        options.signal.addEventListener('abort', () => window.__webmcpAbortCount += 1, {once: true});
      }
    };
    Object.defineProperty(Document.prototype, 'modelContext', {configurable: true, get: () => window.__modelContext});
  });
  await page.goto('/');
});

test('registers narrow tools and returns structured state after a mutation', async ({page}) => {
  await expect(page.getByText('6 page tools ready')).toBeVisible();
  const result = await page.evaluate(async () => {
    const tool = window.__webmcpTools.find(candidate => candidate.name === 'mission_queue_experiment');
    return tool.execute({title: 'Optics sweep', lane: 'research', effort: 4});
  });
  expect(result.ok).toBe(true);
  expect(result.state.item.title).toBe('Optics sweep');
  await expect(page.getByText('Optics sweep', {exact: true})).toBeVisible();
});

test('rejects an invalid mutation without changing local state', async ({page}) => {
  const result = await page.evaluate(async () => {
    const tool = window.__webmcpTools.find(candidate => candidate.name === 'mission_advance');
    return tool.execute({steps: 99});
  });
  expect(result).toMatchObject({ok: false, error: {code: 'invalid_steps'}});
  expect(result.state.tick).toBe(14);
  await expect(page.getByText('014')).toBeVisible();
});

test('the normal UI calls the same focus action', async ({page}) => {
  await page.getByRole('button', {name: /Latency/}).click();
  await expect(page.getByText('Latency', {exact: true}).first()).toBeVisible();
  const dashboard = await page.evaluate(async () => {
    const tool = window.__webmcpTools.find(candidate => candidate.name === 'mission_get_dashboard');
    return tool.execute({});
  });
  expect(dashboard.state.focus).toBe('latency');
});

test('local state survives reload and the UI exports editable JSON', async ({page}) => {
  const advanced = await page.evaluate(async () => window.__webmcpTools.find(tool => tool.name === 'mission_advance').execute({steps: 2}));
  expect(advanced.state.tick).toBe(16);
  await page.reload();
  await expect(page.getByText('016')).toBeVisible();
  const download = page.waitForEvent('download');
  await page.getByRole('button', {name: 'Export JSON'}).click();
  const file = await download;
  expect(file.suggestedFilename()).toBe('mission-control-state.json');
});

test('keeps tools registered across a BFCache pagehide and cleans up on discard', async ({page}) => {
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted: true})));
  expect(await page.evaluate(() => window.__webmcpAbortCount)).toBe(0);
  expect(await page.evaluate(() => window.__webmcpTools.length)).toBe(6);
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted: false})));
  expect(await page.evaluate(() => window.__webmcpAbortCount)).toBe(6);
});
