import { test as base, expect, type Page } from '@playwright/test';

// A fake Supabase for the browser tests: a signed-in session, the profile and entries tables, and save_log(),
// which applies the same upserts and deletes the real database function does. The page clock is controlled
// so a whole day can be stepped through.

export const PRESTON = 'Preston office – 8126 304th Ave SE, Preston, WA 98050';
export type Row = {
  id: string; status: string; start_at: string; end_at: string | null; from_place: string; to_place: string; miles: number | null;
  note: string; partial: boolean; source: string; last_point: null; document: null; shipper: null; commodity: null;
};
type Profile = { name: string; carrier: string; terminal: string; office: string; vehicle: string; co_driver: string; zone: string };

/** A Seattle wall-clock time in November (Pacific Standard Time) as an instant. */
export const pst = (day: string, time: string) => new Date(`${day}T${time}:00-08:00`);

let n = 0;
export function row(status: string, start: Date, end: Date | null, from: string, to = '', miles: number | null = null, note = ''): Row {
  return { id: `seed-${++n}`, status, start_at: start.toISOString(), end_at: end?.toISOString() ?? null, from_place: from, to_place: to, miles, note, partial: false, source: 'manual', last_point: null, document: null, shipper: null, commodity: null };
}

export class Backend {
  rows: Row[] = [];
  profile: Profile = { name: 'Sam Driver', carrier: 'First Due Movers', terminal: '8126 304th Ave SE, Preston, WA', office: '8126 304th Ave SE, Preston, WA', vehicle: '12', co_driver: '', zone: 'America/Los_Angeles' };
  saves: { upserts: Row[]; deletes: string[] }[] = [];
  failNext = false;
  rejected = 0;

  /** Rows for one Seattle day, by the day their start falls on. */
  day(d: string) {
    return this.rows.filter(r => new Date(r.start_at) >= pst(d, '00:00') && new Date(r.start_at) < new Date(pst(d, '00:00').getTime() + 86400000)).sort((a, b) => a.start_at.localeCompare(b.start_at));
  }
  get open() { return this.rows.find(r => r.end_at === null) ?? null; }

  async attach(page: Page) {
    const exp = 4102444800; // 2100: the fake clock never makes the session look expired.
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const jwt = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: 'u1', exp, role: 'authenticated', aud: 'authenticated' })}.sig`;
    const session = { access_token: jwt, refresh_token: 'r', expires_at: exp, expires_in: 3600, token_type: 'bearer', user: { id: 'u1', aud: 'authenticated', role: 'authenticated', email: 'driver@example.com', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } };
    await page.addInitScript(s => { if (!sessionStorage.getItem('signed-out')) localStorage.setItem('sb-jtofziwssarbifugqjnn-auth-token', s); }, JSON.stringify(session));
    await page.route(/supabase\.co/, async route => {
      const req = route.request(), url = req.url();
      if (url.includes('/rest/v1/profiles')) return route.fulfill({ json: this.profile });
      if (url.includes('/rest/v1/entries')) return route.fulfill({ json: [...this.rows].sort((a, b) => a.start_at.localeCompare(b.start_at)) });
      if (url.includes('/rpc/save_log')) {
        if (this.failNext) { this.failNext = false; return route.fulfill({ status: 503, json: { message: 'Failed to fetch' } }); }
        const body = JSON.parse(req.postData() ?? '{}') as { upserts: Row[]; deletes: string[]; profile: Profile | null };
        const next = this.rows.filter(r => !body.deletes.includes(r.id) && !body.upserts.some(u => u.id === r.id)).concat(body.upserts);
        // The real table refuses overlapping periods (entries_no_overlap) and rolls the whole save back.
        const sorted = [...next].sort((a, b) => a.start_at.localeCompare(b.start_at));
        for (let i = 1; i < sorted.length; i++) {
          if (!sorted[i - 1].end_at || sorted[i - 1].end_at! > sorted[i].start_at) {
            this.rejected++;
            return route.fulfill({ status: 409, json: { code: '23P01', message: 'conflicting key value violates exclusion constraint "entries_no_overlap"' } });
          }
        }
        this.saves.push({ upserts: body.upserts, deletes: body.deletes });
        this.rows = next;
        if (body.profile) this.profile = { ...this.profile, ...(body.profile as Profile), co_driver: (body.profile as unknown as { coDriver: string }).coDriver };
        return route.fulfill({ status: 200, json: null });
      }
      if (url.includes('/auth/v1/logout')) return route.fulfill({ status: 204, body: '' });
      return route.fulfill({ json: {} });
    });
  }
}

export const test = base.extend<{ db: Backend; open: (at: Date, tab?: 'Today' | 'LD' | 'History') => Promise<void> }>({
  db: async ({ page }, use) => { const db = new Backend(); await db.attach(page); await use(db); },
  open: async ({ page }, use) => {
    await use(async (at, tab) => {
      await page.clock.install({ time: at });
      await page.goto('/');
      await expect(page.locator('.hos svg').first()).toBeVisible();
      if (tab && tab !== 'Today') await page.getByRole('button', { name: tab, exact: true }).click();
    });
  },
});
export { expect };

/** Moves the page clock on by some minutes, as if the driver kept working. */
export async function later(page: Page, minutes: number) { await page.clock.fastForward(minutes * 60000); }

/** Taps an LD step, picks a place (a suggestion, or Other + typed text) and saves it. */
export async function step(page: Page, button: string | RegExp, place?: { pick?: string; type?: string }, time?: string) {
  await page.locator('.step-buttons button', { hasText: button }).click();
  const dialog = page.locator('dialog[open]');
  if (time) await dialog.locator('input[type=time]').fill(time);
  if (place?.pick) await dialog.locator('.place-options button', { hasText: place.pick }).click();
  if (place?.type) { await dialog.locator('.place-options button', { hasText: 'Other' }).click(); await dialog.locator('.place-input input').fill(place.type); }
  await dialog.locator('button.primary').click();
  await settled(page);
}

/** Waits for a save to finish: the dialog has closed, or it is showing an error. */
export async function settled(page: Page) {
  await page.waitForFunction(() => !document.querySelector('dialog[open]') || !!document.querySelector('dialog[open] .alert, dialog[open] [role=alert]'));
}
