import { test, expect, later, step, settled, row, pst, PRESTON } from './backend';

const D = '2026-11-20';

test('Simple day: a single-location (labor only) job', async ({ page, db, open }) => {
  await open(pst(D, '18:00'));
  await page.getByRole('button', { name: 'Add entry' }).click();
  await page.getByRole('button', { name: /Simple day/ }).click();
  const dialog = page.locator('dialog[open]');
  await dialog.getByRole('button', { name: 'Single location' }).click();
  await expect(dialog.getByPlaceholder('e.g. Seattle')).toHaveCount(0);
  await dialog.getByPlaceholder('e.g. Bellevue').fill('Bellevue');
  await expect(dialog.locator('.plan-preview')).toContainText('mi');
  await dialog.getByRole('button', { name: 'Add day' }).click();
  await expect(dialog).toHaveCount(0);
  expect(db.day(D).filter(r => r.status === 'Driving').map(r => r.note)).toEqual(['To job site', 'Return to office']);
  await page.getByRole('button', { name: 'Edit day' }).click();
  await expect(page.locator('dialog[open] input[placeholder="e.g. Bellevue"]')).toHaveValue('Bellevue');
  await expect(page.locator('dialog[open]')).toContainText('single location');
});

test('Simple day: add, reopen with Edit day, change it, then clear it', async ({ page, db, open }) => {
  await open(pst(D, '18:00'));
  await page.getByRole('button', { name: 'Add entry' }).click();
  await page.getByRole('button', { name: /Simple day/ }).click();
  const dialog = page.locator('dialog[open]');
  await expect(dialog).toContainText('Starts and ends at the Preston office');
  await dialog.getByPlaceholder('e.g. Issaquah').fill('Issaquah');
  await dialog.getByPlaceholder('e.g. Seattle').fill('Seattle');
  await expect(dialog.locator('.plan-preview')).toContainText('mi');
  await dialog.getByRole('button', { name: 'Add day' }).click();
  await expect(dialog).toHaveCount(0);
  expect(db.day(D).length).toBeGreaterThan(5);
  await expect(page.locator('.hos-remarks li').first()).toContainText('Pre-trip');

  await page.getByRole('button', { name: 'Edit day' }).click();
  await expect(page.locator('dialog[open] input[placeholder="e.g. Issaquah"]')).toHaveValue('Issaquah');
  await page.locator('dialog[open] select').selectOption('60');
  await page.locator('dialog[open]').getByRole('button', { name: 'Save day' }).click();
  await settled(page);
  const lunch = db.day(D).find(r => r.note === 'Lunch break')!;
  expect(new Date(lunch.end_at!).getTime() - new Date(lunch.start_at).getTime()).toBe(3600000);

  await page.getByRole('button', { name: 'Clear day' }).click();
  await page.locator('dialog[open] button.danger').click();
  await expect(page.getByText('No entries for this day')).toBeVisible();
  expect(db.day(D)).toHaveLength(0);
});

test('adding a day over existing entries explains the clash instead of overlapping', async ({ page, db, open }) => {
  db.rows.push(row('On duty', pst(D, '09:00'), pst(D, '10:00'), PRESTON));
  await open(pst(D, '18:00'));
  await page.getByRole('button', { name: 'Add entry' }).click();
  await page.getByRole('button', { name: /Simple day/ }).click();
  const dialog = page.locator('dialog[open]');
  await dialog.getByPlaceholder('e.g. Issaquah').fill('Issaquah');
  await dialog.getByPlaceholder('e.g. Seattle').fill('Seattle');
  await dialog.locator('.replace-note input').uncheck();
  await dialog.getByRole('button', { name: 'Add day' }).click();
  await expect(dialog.locator('.alert')).toContainText('already has 1 entry');
  expect(db.day(D)).toHaveLength(1);
});

test('Fill in a day step by step, past midnight, then fix it', async ({ page, db, open }) => {
  await open(pst('2026-11-21', '12:00'));
  await page.getByRole('button', { name: 'Previous day' }).click();
  await page.getByRole('button', { name: 'Add entry' }).click();
  await page.getByRole('button', { name: /step by step/ }).click();
  const dialog = page.locator('dialog[open]');
  const rowAt = (i: number) => dialog.locator('.steps li').nth(i);
  await rowAt(0).locator('input[type=time]').fill('20:00');
  await dialog.getByRole('button', { name: 'Start driving' }).click();
  await rowAt(1).locator('input[type=time]').fill('20:15');
  await dialog.getByRole('button', { name: 'Arrive · post-trip' }).click();
  await rowAt(2).locator('input[type=time]').fill('01:00');
  await rowAt(2).locator('input[list]').fill('Hotel – Spokane, WA');
  await dialog.getByRole('button', { name: 'Clock out' }).click();
  await rowAt(3).locator('input[type=time]').fill('01:15');
  await dialog.getByRole('button', { name: 'Save day' }).click();
  await expect(dialog).toHaveCount(0);
  const rows = [...db.rows].sort((a, b) => a.start_at.localeCompare(b.start_at));
  expect(rows.map(r => r.status)).toEqual(['On duty', 'Driving', 'On duty']);
  expect(rows[2].start_at).toBe(pst('2026-11-21', '01:00').toISOString());
  expect(rows[2].end_at).toBe(pst('2026-11-21', '01:15').toISOString());
  expect(rows[1].miles).toBeGreaterThan(200);

  // The next day's chart shows the part after midnight, and Edit day there opens the whole shift.
  await page.getByRole('button', { name: 'Next day' }).click();
  await expect(page.locator('.hos svg').first()).toHaveAttribute('aria-label', /Driving 1:00/);
  await page.getByRole('button', { name: 'Edit day' }).click();
  await expect(page.locator('dialog[open] .steps li')).toHaveCount(4);
  await page.locator('dialog[open]').getByRole('button', { name: 'Cancel' }).click();

  await page.getByRole('button', { name: 'Previous day' }).click();
  await page.getByRole('button', { name: 'Edit day' }).click();
  const steps = page.locator('dialog[open] .steps li');
  await expect(steps).toHaveCount(4);
  await expect(steps.nth(2).locator('select')).toHaveValue('posttrip');
  await steps.nth(1).locator('input[type=number]').fill('250');
  await page.locator('dialog[open]').getByRole('button', { name: 'Save day' }).click();
  await expect(page.locator('dialog[open]')).toHaveCount(0);
  expect(db.rows).toHaveLength(3);
  expect(db.rows.find(r => r.status === 'Driving')!.miles).toBe(250);
});

test('Advanced entry: add, edit, delete', async ({ page, db, open }) => {
  await open(pst(D, '18:00'));
  await page.getByRole('button', { name: 'Add entry' }).click();
  await page.getByRole('button', { name: /Advanced entry/ }).click();
  const dialog = page.locator('dialog[open]');
  await dialog.getByPlaceholder('Starting address').fill('Seattle');
  await dialog.getByPlaceholder('Destination address').fill('Bellevue');
  await dialog.getByPlaceholder('Enter actual miles').fill('11.2');
  await dialog.getByRole('button', { name: 'Save entry' }).click();
  await expect(dialog).toHaveCount(0);
  expect(db.rows).toHaveLength(1);
  expect(db.rows[0]).toMatchObject({ status: 'Driving', miles: 11.2 });

  await page.locator('.entry button[aria-label^="Edit"]').click();
  await page.locator('dialog[open] select').first().selectOption('On duty');
  await page.locator('dialog[open]').getByRole('button', { name: 'Save entry' }).click();
  await settled(page);
  expect(db.rows[0].status).toBe('On duty');

  await page.locator('.entry button[aria-label^="Edit"]').click();
  await page.locator('dialog[open]').getByRole('button', { name: 'Delete' }).click();
  await page.locator('dialog[open]').getByRole('button', { name: 'Delete entry' }).click();
  await settled(page);
  expect(db.rows).toHaveLength(0);
});

test('a failed save shows an error and keeps the form open', async ({ page, db, open }) => {
  await open(pst(D, '07:00'), 'LD');
  db.failNext = true;
  await step(page, 'Clock in', { pick: 'Preston office' });
  await expect(page.locator('dialog[open] .alert')).toBeVisible();
  expect(db.rows).toHaveLength(0);
  await page.locator('dialog[open] button.primary').click();
  await expect(page.locator('dialog[open]')).toHaveCount(0);
  expect(db.open).not.toBeNull();
});

test('a phone in another time zone still logs Seattle time', async ({ browser }) => {
  const context = await browser.newContext({ timezoneId: 'America/New_York' });
  const page = await context.newPage();
  const { Backend } = await import('./backend');
  const db = new Backend();
  await db.attach(page);
  await page.clock.install({ time: pst(D, '07:00') });
  await page.goto('/');
  await page.getByRole('button', { name: 'LD', exact: true }).click();
  await step(page, 'Clock in', { pick: 'Preston office' });
  expect(db.open?.start_at).toBe(pst(D, '07:00').toISOString());
  await context.close();
});

test('History groups LD days and opens a day on Today', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst('2026-11-17', '08:00'), pst('2026-11-17', '12:00'), PRESTON, 'Hotel – Spokane, WA', 262, 'Driving'));
  db.rows.push(row('Driving', pst('2026-11-18', '08:00'), pst('2026-11-18', '12:00'), 'Hotel – Spokane, WA', PRESTON, 262, 'Driving'));
  db.rows.push(row('Driving', pst('2026-11-19', '08:00'), pst('2026-11-19', '09:00'), PRESTON, 'Issaquah', 9, 'To load'));
  await open(pst(D, '07:00'), 'History');
  await expect(page.locator('.ld-trip')).toHaveCount(1);
  await expect(page.locator('.ld-trip-head')).toContainText('Nov 17 – 18');
  await expect(page.locator('.ld-trip-head')).toContainText('2 days · 524.0 mi');
  await page.getByRole('button', { name: /Open Thursday, November 19/ }).click();
  await expect(page.getByRole('button', { name: 'Back to history' })).toBeVisible();
  await expect(page.locator('.date-label input')).toHaveValue('2026-11-19');
});

test('Inspection view shows today and the previous 7 days', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst('2026-11-18', '08:00'), pst('2026-11-18', '12:00'), PRESTON, 'Hotel – Spokane, WA', 262, 'Driving'));
  await open(pst(D, '09:00'), 'LD');
  await page.getByRole('button', { name: 'Inspection view' }).click();
  const dialog = page.locator('dialog[open]');
  await expect(dialog.locator('.inspect-day')).toHaveCount(8);
  await expect(dialog.locator('.inspect-day').nth(2)).toContainText('262.0 mi driving');
  await expect(dialog.locator('.inspect-day').nth(1)).toContainText('Off duty all day');
  await expect(dialog).toContainText('Sam Driver');
});

test('daylight-saving day in November has 25 hours on the chart', async ({ page, db, open }) => {
  db.rows.push(row('On duty', new Date('2026-11-01T08:00:00-08:00'), new Date('2026-11-01T16:00:00-08:00'), PRESTON));
  await open(pst('2026-11-02', '09:00'));
  await page.getByRole('button', { name: 'Previous day' }).click();
  await expect(page.locator('.hos svg').first()).toHaveAttribute('aria-label', /On duty 8:00/);
  await expect(page.locator('.hos-total.sum').first()).toHaveText('25:00');
});

test('driver details save, and the lock button signs out', async ({ page, db, open }) => {
  await open(pst(D, '09:00'));
  await page.getByRole('button', { name: 'Driver and vehicle settings' }).click();
  const dialog = page.locator('dialog[open]');
  await expect(dialog.locator('label', { hasText: 'Co-driver' })).toHaveCount(0);
  await expect(dialog.locator('label', { hasText: 'Home terminal' })).toHaveCount(0);
  await expect(dialog).toContainText('Office: 8126 304th Ave SE, Preston, WA 98050');
  await dialog.locator('label', { hasText: 'Truck number' }).locator('input').fill('14');
  await dialog.getByRole('button', { name: 'Save details' }).click();
  await expect(dialog).toHaveCount(0);
  expect(db.profile.vehicle).toBe('14');
  expect(db.profile.office).toBe('8126 304th Ave SE, Preston, WA 98050');
  expect(db.profile.terminal).toBe('8126 304th Ave SE, Preston, WA 98050');
  await page.evaluate(() => sessionStorage.setItem('signed-out', '1'));
  await page.getByRole('button', { name: 'Lock log' }).click();
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
});

test('a day in progress keeps the LD state across a reload', async ({ page, db, open }) => {
  await open(pst(D, '07:00'), 'LD');
  await step(page, 'Clock in', { pick: 'Preston office' });
  await later(page, 20);
  await step(page, 'Start driving', { pick: 'Preston office' });
  await page.reload();
  await page.getByRole('button', { name: 'LD', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Driving' })).toBeVisible();
  expect(db.day(D)).toHaveLength(2);
});
