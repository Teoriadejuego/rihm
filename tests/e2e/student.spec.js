import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { fixture, emptyFixture, bundle, protect } from '../js/fixtures.js';

async function serveFixture(page, provider) {
  const requests = [], unexpected = [], errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== 'http://127.0.0.1:4173') { unexpected.push(url.origin); await route.abort(); return; }
    if (url.pathname.endsWith('/data/public_manifest.json') || url.pathname.endsWith('/data/public_results.json')) {
      requests.push(url.pathname);
      const current = provider();
      if (current.error) { await route.fulfill({ status: 503, body: 'Unavailable' }); return; }
      await route.fulfill({ contentType: 'application/json; charset=utf-8', body: url.pathname.endsWith('manifest.json') ? JSON.stringify(current.manifest) : current.text });
    } else await route.continue();
  });
  return { requests, unexpected, errors };
}

test('loads verified aggregates and filters locally without private service requests', async ({ page }, testInfo) => {
  const b = bundle(), log = await serveFixture(page, () => b);
  await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('Publication checked');
  await expect(page.locator('#demoNotice')).toContainText('Synthetic demonstration');
  await expect(page.locator('#groupWindow')).toContainText('4 Mar 2020');
  await expect(page.locator('#matrixTable tbody td')).toHaveCount(16);
  await expect(page.locator('.indicator-block')).toHaveCount(4);
  await expect(page.locator('#compare .difference-row')).toHaveCount(4);
  await page.getByLabel('Reference country', { exact: true }).selectOption('Spain');
  await page.getByLabel('Gender', { exact: true }).selectOption('female');
  await page.getByLabel('Matrix sample', { exact: true }).selectOption('international');
  await page.getByRole('checkbox', { name: 'Selfish', exact: true }).uncheck();
  await expect(page.locator('.indicator-block')).toHaveCount(3);
  await expect(page.locator('#compare .difference-row')).toHaveCount(3);
  await expect(page.locator('#matrixTable caption')).toContainText('Spain');
  const row = b.data.cells.find((c) => c.scope === 'class' && c.gender === 'female' && c.behaviour === 'altruist');
  await expect(page.locator('[data-indicator="altruist"] .group .bar-value')).toHaveText(`${row.percentage.toFixed(1)}%`);
  const reference = b.data.cells.find((c) => c.scope === 'international' && c.country === 'Spain' && c.gender === 'female' && c.behaviour === 'altruist');
  const gap = Math.round((row.percentage - reference.percentage) * 10) / 10;
  await expect(page.locator('[data-difference="altruist"] .difference-value')).toHaveText(`${gap > 0 ? '+' : ''}${gap.toFixed(1)} pp`);
  await page.getByText('Compare the exact counts and denominators', { exact: true }).click();
  await expect(page.locator('#comparisonTable')).toContainText(`${row.count} / ${row.denominator_n}`);
  expect(log.requests).toHaveLength(2); expect(log.unexpected).toEqual([]); expect(log.errors).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath('student-desktop.png'), fullPage: true });
});

test('keeps the last verified snapshot during failure then atomically refreshes with filters intact', async ({ page }) => {
  const first = bundle(), next = bundle(fixture({ id: 'demo-browser-2', seed: 4 })); let served = first;
  await serveFixture(page, () => served); await page.goto('./'); await expect(page.locator('#publicationMeta')).toContainText('demo-browser-1');
  await page.getByLabel('Reference country', { exact: true }).selectOption('Spain'); await page.getByLabel('Gender', { exact: true }).selectOption('male');
  await page.getByRole('checkbox', { name: 'Selfish', exact: true }).uncheck();
  const before = await page.locator('[data-indicator="altruist"] .group .bar-value').textContent();
  served = { manifest: next.manifest, text: first.text };
  await page.getByRole('button', { name: 'Check for updates' }).click(); await expect(page.locator('#dataStatus')).toContainText('last verified publication remains');
  await expect(page.locator('#publicationMeta')).toContainText('demo-browser-1'); await expect(page.locator('[data-indicator="altruist"] .group .bar-value')).toHaveText(before);
  served = next; await page.getByRole('button', { name: 'Check for updates' }).click(); await expect(page.locator('#publicationMeta')).toContainText('demo-browser-2');
  await expect(page.getByLabel('Reference country', { exact: true })).toHaveValue('Spain'); await expect(page.getByLabel('Gender', { exact: true })).toHaveValue('male'); await expect(page.getByRole('checkbox', { name: 'Selfish', exact: true })).not.toBeChecked();
  const row = next.data.cells.find((c) => c.scope === 'class' && c.gender === 'male' && c.behaviour === 'altruist');
  await expect(page.locator('[data-indicator="altruist"] .group .bar-value')).toHaveText(`${row.percentage.toFixed(1)}%`);
});

test('polls only visible pages and checks when visibility returns', async ({ page }) => {
  await page.clock.install(); const b = bundle(), log = await serveFixture(page, () => b);
  await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('Publication checked'); expect(log.requests).toHaveLength(2);
  await page.clock.fastForward(60000); await expect.poll(() => log.requests.length).toBe(3);
  await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' }); document.dispatchEvent(new Event('visibilitychange')); });
  await page.clock.fastForward(120000); expect(log.requests).toHaveLength(3);
  await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' }); document.dispatchEvent(new Event('visibilitychange')); });
  await expect.poll(() => log.requests.length).toBe(4);
});

test('keeps protected values hidden across charts, table and accessible matrix', async ({ page }) => {
  const data = fixture(); protect(data.cells.find((c) => c.scope === 'class' && c.gender === 'all' && c.behaviour === 'altruist')); protect(data.matrix_cells.find((c) => c.scope === 'class' && c.gender === 'all' && c.compassion_level === 4 && c.envy_level === 1));
  await serveFixture(page, () => bundle(data)); await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('Publication checked');
  await expect(page.locator('[data-indicator="altruist"] .group .bar-value')).toHaveText('Protected'); await expect(page.locator('[data-indicator="altruist"] .difference')).toHaveText('Unavailable');
  await expect(page.locator('[data-difference="altruist"] .difference-value')).toHaveText('Unavailable'); await expect(page.locator('[data-difference="altruist"] .difference-fill')).toHaveCount(0);
  await expect(page.locator('#matrixTable td').first()).toHaveAccessibleName('Compassion 4, envy 1: Protected');
  await page.getByText('Compare the exact counts and denominators', { exact: true }).click(); await expect(page.locator('#comparisonTable tbody tr').first()).toContainText('Protected');
});

test('supports mobile and keyboard access without losing publication metadata', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 }); const log = await serveFixture(page, () => bundle()); await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('Publication checked');
  await page.getByLabel('Reference country', { exact: true }).focus(); await page.keyboard.press('s'); await page.keyboard.press('Enter');
  await expect(page.getByLabel('Reference country', { exact: true })).toBeFocused();
  await expect(page.locator('#publicationMeta')).toBeVisible(); await expect(page.locator('#matrixTable')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true); expect(log.errors).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath('student-mobile.png'), fullPage: true });
});

test('legacy empty publication and initial network failure remain usable', async ({ page }) => {
  let served = { error: true }; await serveFixture(page, () => served); await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('could not be loaded');
  served = bundle(emptyFixture()); await page.getByRole('button', { name: 'Check for updates' }).click(); await expect(page.locator('#dataStatus')).toContainText('has not published a group yet');
  await expect(page.getByRole('heading', { name: 'How to read this experiment' })).toBeVisible(); await expect(page.getByLabel('Reference country', { exact: true })).toHaveCount(0);
});

test('published strings cannot inject markup', async ({ page }) => {
  const data = fixture(); data.metadata.data_note = '<img src=x onerror="window.injected=true">'; data.metadata.classification_version = '<img src=x onerror="window.injected=true">';
  await serveFixture(page, () => bundle(data)); await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('Publication checked'); await page.getByText('Publication and method details', { exact: true }).click();
  await expect(page.locator('.publication-list')).toContainText('<img src=x'); expect(await page.evaluate(() => window.injected)).toBeUndefined();
});

test('aggregate views meet automated accessibility checks at desktop and mobile sizes', async ({ page }) => {
  await serveFixture(page, () => bundle()); await page.goto('./'); await expect(page.locator('#dataStatus')).toContainText('Publication checked');
  await page.getByText('Compare the exact counts and denominators', { exact: true }).click();
  for (const width of [1280, 390]) {
    await page.setViewportSize({ width, height: 900 });
    const report = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
    expect(report.violations).toEqual([]);
  }
});

