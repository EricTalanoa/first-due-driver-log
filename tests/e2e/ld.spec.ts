import { test, expect, later, step, row, pst, PRESTON } from './backend';

const D = '2026-11-20';

test('a whole LD day tapped through live, office to hotel', async ({ page, db, open }) => {
  await open(pst(D, '06:30'), 'LD');
  await expect(page.getByRole('heading', { name: 'Off the clock' })).toBeVisible();
  await expect(page.locator('.hos-clocks')).toHaveCount(0);

  await step(page, 'Clock in', { pick: 'Preston office' });
  await expect(page.getByRole('heading', { name: 'Pre-trip inspection' })).toBeVisible();
  await later(page, 15);
  await step(page, 'Start driving', { pick: 'Preston office' });
  await later(page, 165);
  await step(page, 'Fuel stop', { type: 'Ellensburg' });
  await later(page, 15);
  await step(page, 'Start driving', { pick: 'Ellensburg' });
  await later(page, 105);
  await step(page, /^Lunch/, { type: 'Spokane' });
  await later(page, 30);
  await step(page, 'Start driving', { pick: 'Spokane' });
  await later(page, 20);
  await step(page, 'Arrive · post-trip', { type: 'Hotel – Spokane Valley' });
  await later(page, 15);
  await step(page, 'Clock out', { pick: 'Hotel – Spokane Valley' });

  await expect(page.getByRole('heading', { name: 'Off the clock' })).toBeVisible();
  const rows = db.day(D);
  expect(rows.map(r => r.status)).toEqual(['On duty', 'Driving', 'On duty', 'Driving', 'Off duty', 'Driving', 'On duty']);
  expect(rows.map(r => r.note.split(' | ')[0])).toEqual(['Pre-trip inspection', 'Driving', 'Fueling', 'Driving', 'Lunch break', 'Driving', 'Post-trip inspection']);
  expect(rows[0].note).toContain('LD trip');
  expect(rows[1]).toMatchObject({ to_place: 'Ellensburg', miles: 92.9 });
  expect(db.open).toBeNull();
  // Remarks list every change plus the clock out.
  await expect(page.locator('.hos-remarks li')).toHaveCount(8);
  await expect(page.locator('.hos-remarks li').last()).toContainText('Clock out');

  await page.getByRole('button', { name: 'History', exact: true }).click();
  await expect(page.locator('.ld-trip')).toHaveCount(1);
  await expect(page.locator('.ld-trip-head')).toContainText('1 day');
});

test('next morning suggests the hotel from last night, and the hours clocks appear once clocked in', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst('2026-11-19', '13:00'), pst('2026-11-19', '17:00'), PRESTON, 'Hotel – Spokane, WA', 262, 'Driving'));
  await open(pst(D, '07:00'), 'LD');
  await expect(page.getByText('Last stop')).toHaveCount(0);
  await page.locator('.step-buttons button', { hasText: 'Clock in' }).click();
  const options = page.locator('dialog[open] .place-options button');
  await expect(options).toHaveText(['Hotel – Spokane, WA', 'Preston office', 'Other']);
  await expect(options.first()).toHaveAttribute('aria-pressed', 'true');
  await page.locator('dialog[open] button.primary').click();
  await expect(page.locator('.hos-clocks')).toBeVisible();
  expect(db.open).toMatchObject({ from_place: 'Hotel – Spokane, WA' });
});

test('an older LD trip is not shown on today\'s LD page', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst('2026-11-16', '13:00'), pst('2026-11-16', '17:00'), PRESTON, 'Hotel – Spokane, WA', 262, 'Driving'));
  await open(pst(D, '07:00'), 'LD');
  await expect(page.getByText('Nothing logged yet today')).toBeVisible();
  await page.locator('.step-buttons button', { hasText: 'Clock in' }).click();
  await expect(page.locator('dialog[open] .place-options button')).toHaveText(['Preston office', 'Other']);
});

test('a step saved a minute ahead does not block the next one (reported bug)', async ({ page, db, open }) => {
  db.rows.push(row('On duty', pst(D, '07:18'), pst(D, '08:15'), PRESTON, '', null, 'Pre-trip inspection | LD trip'));
  db.rows.push(row('Driving', pst(D, '08:20'), null, 'Maple Valley', '', null, 'Driving'));
  await open(new Date(pst(D, '08:19').getTime() + 14000), 'LD');
  await step(page, 'Quick break', { type: 'Black Diamond' }, '08:21');
  await expect(page.locator('dialog[open]')).toHaveCount(0);
  expect(db.open).toMatchObject({ status: 'Off duty', from_place: 'Black Diamond' });
});

test('a time before the current step says when it started', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst(D, '09:00'), null, PRESTON, '', null, 'Driving'));
  await open(pst(D, '10:00'), 'LD');
  await step(page, 'Fuel stop', { type: 'Ellensburg' }, '08:30');
  await expect(page.locator('dialog[open] .alert')).toContainText('started at 9:00 AM');
});

test('Clear day removes everything, including the drive in progress', async ({ page, db, open }) => {
  db.rows.push(row('On duty', pst(D, '07:00'), pst(D, '07:15'), PRESTON, '', null, 'Pre-trip inspection | LD trip'));
  db.rows.push(row('Driving', pst(D, '07:15'), null, PRESTON, '', null, 'Driving'));
  db.rows.push(row('On duty', pst('2026-11-19', '07:00'), pst('2026-11-19', '15:00'), PRESTON));
  await open(pst(D, '09:00'), 'LD');
  await page.locator('.ld-clear button').click();
  await expect(page.locator('dialog[open]')).toContainText("including what you're recording now (driving)");
  await page.locator('dialog[open] button.danger').click();
  await expect(page.getByRole('heading', { name: 'Off the clock' })).toBeVisible();
  expect(db.day(D)).toHaveLength(0);
  expect(db.open).toBeNull();
  expect(db.day('2026-11-19')).toHaveLength(1);
});

test('switching drivers logs riding as on duty, and taking the wheel back drives', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst(D, '07:00'), null, PRESTON, '', null, 'Driving'));
  await open(pst(D, '11:00'), 'LD');
  await step(page, 'Switch drivers', { type: 'Ellensburg' });
  await expect(page.locator('dialog[open]')).toHaveCount(0);
  expect(db.open).toMatchObject({ status: 'On duty', note: 'Riding – co-driver driving' });
  await later(page, 120);
  await step(page, 'Take the wheel', { type: 'Moses Lake' });
  expect(db.open).toMatchObject({ status: 'Driving', from_place: 'Moses Lake' });
});

test('an unknown city asks for the miles before saving', async ({ page, db, open }) => {
  db.rows.push(row('Driving', pst(D, '07:00'), null, PRESTON, '', null, 'Driving'));
  await open(pst(D, '11:00'), 'LD');
  await page.locator('.step-buttons button', { hasText: 'Start unload' }).click();
  const dialog = page.locator('dialog[open]');
  await dialog.locator('.place-options button', { hasText: 'Other' }).click();
  await dialog.locator('.place-input input').fill('Missoula, MT');
  await expect(dialog.locator('input[type=number]')).toHaveAttribute('placeholder', /City not recognized/);
  await dialog.locator('input[type=number]').fill('412');
  await dialog.locator('button.primary').click();
  await expect(dialog).toHaveCount(0);
  expect(db.day(D)[0]).toMatchObject({ to_place: 'Missoula, MT', miles: 412 });
});

test('phone and website at once: a stale page refreshes instead of saving a clash', async ({ browser }) => {
  const { Backend } = await import('./backend');
  const db = new Backend();
  const pages = [];
  for (let i = 0; i < 2; i++) {
    const page = await (await browser.newContext()).newPage();
    await db.attach(page);
    await page.clock.install({ time: pst(D, '07:00') });
    await page.goto('/');
    await page.getByRole('button', { name: 'LD', exact: true }).click();
    pages.push(page);
  }
  const [phone, web] = pages;
  await step(phone, 'Clock in', { pick: 'Preston office' });
  expect(db.open).not.toBeNull();
  // The website still shows "Off the clock" and tries to clock in too.
  await later(web, 5);
  await step(web, 'Clock in', { pick: 'Preston office' });
  expect(db.rejected).toBe(1);
  await expect(web.locator('dialog[open] .alert')).toContainText('changed on another device');
  await web.locator('dialog[open] button.secondary').click();
  await expect(web.getByRole('heading', { name: 'Pre-trip inspection' })).toBeVisible();
  expect(db.rows.filter(r => r.end_at === null)).toHaveLength(1);
});

test('coming back to the page picks up changes made on the phone', async ({ page, db, open }) => {
  await open(pst(D, '07:00'), 'LD');
  db.rows.push(row('On duty', pst(D, '07:05'), null, PRESTON, '', null, 'Pre-trip inspection | LD trip'));
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { value: false, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
  await expect(page.getByRole('heading', { name: 'Pre-trip inspection' })).toBeVisible();
});
