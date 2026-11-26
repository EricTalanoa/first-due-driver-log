import { describe, expect, it } from 'vitest';
import { activityOf, shiftOf, chartSegments, estimateMiles, hosClocks, isLdDay, nextSteps, stepAt, stepTime, toEntries, toSteps, hotel, LD_MARK, PRESTON, type Step } from '../../lib/hos';
import { bounds, epoch, validateLog, initialLog, type Entry } from '../../lib/log';

const z = 'America/Los_Angeles';
const H = 3600000;
const at = (day: string, t: string) => epoch(`${day}T${t}`, z);

/** Builds a timeline the way the editor does: each time rolls past midnight if it isn't after the one before. */
function steps(day: string, list: [string, Step['act'], string, number?][]): Step[] {
  const out: Step[] = [];
  for (const [t, act, place, miles] of list) out.push({ id: crypto.randomUUID(), time: stepTime(day, t, z, out.at(-1)?.time), act, place, miles: miles ?? null });
  return out;
}
const ldDay = (day = '2026-11-20') => steps(day, [
  ['06:30', 'pretrip', PRESTON], ['06:45', 'drive', PRESTON], ['09:30', 'fuel', 'Ellensburg'], ['09:45', 'drive', 'Ellensburg'],
  ['11:30', 'lunch', 'Spokane'], ['12:00', 'unload', 'Spokane'], ['15:00', 'drive', 'Spokane'],
  ['16:30', 'posttrip', hotel('Spokane Valley')], ['16:45', 'clockout', hotel('Spokane Valley')],
]);
const work = (start: number, end: number, status: Entry['status'] = 'On duty'): Entry =>
  ({ id: crypto.randomUUID(), status, start, end, from: 'Seattle', to: status === 'Driving' ? 'Bellevue' : '', miles: status === 'Driving' ? 10 : null, note: '', partial: false, source: 'manual' });

describe('LD timeline', () => {
  it('turns steps into entries and back', () => {
    const s = ldDay();
    const es = toEntries(s, LD_MARK);
    expect(es.map(e => e.status)).toEqual(['On duty', 'Driving', 'On duty', 'Driving', 'Off duty', 'On duty', 'Driving', 'On duty']);
    expect(es[0].note.endsWith(LD_MARK)).toBe(true);
    expect(es[1].miles).toBe(92.9);
    expect(es[3].to).toBe('Spokane');
    expect(() => validateLog({ ...initialLog(), entries: es })).not.toThrow();
    expect(toSteps(es).map(x => [x.act, x.time])).toEqual(s.map(x => [x.act, x.time]));
  });
  it('keeps typed miles over the estimate', () => {
    const s = ldDay(); s[1].miles = 88;
    expect(toEntries(s)[1].miles).toBe(88);
  });
  it('leaves miles empty when a city is unknown', () => {
    const s = steps('2026-11-20', [['07:00', 'pretrip', 'Nowhereville'], ['07:15', 'drive', 'Nowhereville'], ['09:00', 'clockout', 'Somewhere else']]);
    expect(toEntries(s)[1].miles).toBeNull();
  });
  it('needs a clock out at the end and times in order', () => {
    const s = ldDay();
    expect(() => toEntries(s.slice(0, -1))).toThrow(/Clock out/);
    const bad = [...s]; bad[3] = { ...bad[3], time: bad[2].time };
    expect(() => toEntries(bad)).toThrow(/after step/);
    expect(() => toEntries([])).toThrow(/clock-in/);
  });
  it('reads gaps between entries as breaks', () => {
    const es = toEntries(ldDay());
    const gapped = [es[0], { ...es[1], start: es[1].start + 15 * 60000 }];
    expect(toSteps(gapped).map(x => x.act)).toEqual(['pretrip', 'break', 'drive', 'clockout']);
  });
  it('rolls a time past midnight onto the next day', () => {
    const s = steps('2026-11-20', [['20:00', 'pretrip', PRESTON], ['20:15', 'drive', PRESTON], ['01:00', 'posttrip', 'Boise'], ['01:15', 'clockout', 'Boise']]);
    const es = toEntries(s);
    expect(es[1].end).toBe(at('2026-11-21', '01:00'));
    const day2 = chartSegments(es, '2026-11-21', z, Date.parse('2027-01-01'));
    const total = day2.segments.reduce((n, g) => n + g.end - g.start, 0);
    expect(total).toBe(24 * H);
    expect(day2.segments.filter(g => g.status === 'Driving').reduce((n, g) => n + g.end - g.start, 0)).toBe(H);
  });
});

describe('activities and next steps', () => {
  it('reads old and new notes', () => {
    expect(activityOf({ status: 'On duty', note: 'Unloading (job 2)' })).toBe('unload');
    expect(activityOf({ status: 'On duty', note: 'Pre-trip inspection / prep at office | Simple day entry: x' })).toBe('pretrip');
    expect(activityOf({ status: 'Off duty', note: 'Lunch break' })).toBe('lunch');
    expect(activityOf({ status: 'Driving', note: 'To load' })).toBe('drive');
    expect(activityOf({ status: 'On duty', note: 'Fueling' })).toBe('fuel');
    expect(activityOf({ status: 'On duty', note: '' })).toBe('work');
    expect(activityOf({ status: 'Off duty', note: '' })).toBe('off');
  });
  it('offers the right next steps', () => {
    expect(nextSteps(null)).toEqual(['pretrip']);
    expect(nextSteps('drive')).toContain('fuel');
    expect(nextSteps('drive')).not.toContain('clockout');
    expect(nextSteps('riding')[0]).toBe('drive');
    expect(nextSteps('posttrip')[0]).toBe('clockout');
  });
});

describe('places and miles', () => {
  it('estimates road miles between known places', () => {
    expect(estimateMiles(PRESTON, 'Ellensburg')).toBe(92.9);
    expect(estimateMiles(PRESTON, hotel('Spokane'))).toBeCloseTo(262.5, 1);
    expect(estimateMiles('123 Main St, Issaquah, WA 98027', 'Seattle')).toBeGreaterThan(10);
    expect(estimateMiles(PRESTON, 'Nowhereville')).toBeNull();
  });
  it('spots LD days', () => {
    const d = (to: string, note = '') => [{ ...work(0, 1, 'Driving'), from: PRESTON, to, note }];
    expect(isLdDay(d('Clyde Hill'))).toBe(false);
    expect(isLdDay(d('Kent'))).toBe(false);
    expect(isLdDay(d('Pullman'))).toBe(true);
    expect(isLdDay(d(hotel('Issaquah')))).toBe(true);
    expect(isLdDay(d('Seattle', 'Pre-trip inspection' + LD_MARK))).toBe(true);
    expect(isLdDay(d('Seattle', 'Walla Walla LD'))).toBe(true);
    // "LD" inside a word is not a tag.
    expect(isLdDay(d('Seattle', 'Old load'))).toBe(false);
  });
});

describe('chart', () => {
  it('fills blank time as off duty and adds up to 24 hours', () => {
    const es = toEntries(ldDay());
    const c = chartSegments(es, '2026-11-20', z, Date.parse('2027-01-01'));
    const tot = (s: string) => c.segments.filter(g => g.status === s).reduce((n, g) => n + g.end - g.start, 0) / H;
    expect(tot('Driving')).toBe(6);
    expect(tot('On duty')).toBe(3.75);
    expect(tot('Off duty')).toBe(14.25);
    expect(c.segments[0]).toMatchObject({ status: 'Off duty', filled: true });
    expect(c.segments.at(-1)).toMatchObject({ status: 'Off duty', filled: true });
  });
  it('stops at now for today', () => {
    const now = at('2026-11-20', '10:00');
    const c = chartSegments(toEntries(ldDay()), '2026-11-20', z, now);
    expect(c.upto).toBe(now);
    expect(c.segments.at(-1)!.end).toBe(now);
  });
  it('handles daylight-saving days (23 and 25 hours)', () => {
    const [s1, e1] = bounds('2026-03-08', z);
    expect((e1 - s1) / H).toBe(23);
    const [s2, e2] = bounds('2026-11-01', z);
    expect((e2 - s2) / H).toBe(25);
    const c = chartSegments([], '2026-11-01', z, Date.parse('2027-01-01'));
    expect(c.segments.reduce((n, g) => n + g.end - g.start, 0) / H).toBe(25);
  });
  it('rejects a time skipped by daylight saving', () => {
    expect(() => epoch('2026-03-08T02:30', z)).toThrow(/does not exist/);
  });
  it('treats an open entry as running until now', () => {
    const now = at('2026-11-20', '12:00');
    const open: Entry = { ...work(at('2026-11-20', '11:00'), 0, 'Driving'), end: null };
    const c = chartSegments([open], '2026-11-20', z, now);
    expect(c.segments.at(-1)).toMatchObject({ status: 'Driving', end: now });
  });
});

describe('hours of service', () => {
  it('counts the day so far', () => {
    const c = hosClocks(toEntries(ldDay()), at('2026-11-20', '13:00'));
    expect(c.drive / H).toBe(6.5);
    expect(c.window / H).toBe(7.5);
    expect(c.breakDue / H).toBe(8);
    expect(c.cycle / H).toBe(64);
  });
  it('goes negative past 11 hours of driving and the 14-hour window', () => {
    const d = '2026-11-20';
    const es = [work(at(d, '05:00'), at(d, '05:30')), work(at(d, '05:30'), at(d, '11:30'), 'Driving'), work(at(d, '11:30'), at(d, '12:00'), 'Off duty'), work(at(d, '12:00'), at(d, '18:00'), 'Driving'), work(at(d, '18:00'), at(d, '19:30'))];
    const c = hosClocks(es, at(d, '19:30'));
    expect(c.drive / H).toBe(-1);
    expect(c.window / H).toBe(-0.5);
  });
  it('needs a 30-minute break after 8 hours of driving; on-duty time counts as a break', () => {
    const d = '2026-11-20';
    const straight = [work(at(d, '06:00'), at(d, '14:30'), 'Driving')];
    expect(hosClocks(straight, at(d, '14:30')).breakDue / H).toBe(-0.5);
    const withUnload = [work(at(d, '06:00'), at(d, '10:00'), 'Driving'), work(at(d, '10:00'), at(d, '10:30')), work(at(d, '10:30'), at(d, '14:30'), 'Driving')];
    expect(hosClocks(withUnload, at(d, '14:30')).breakDue / H).toBe(4);
  });
  it('starts a new shift after 10 hours off', () => {
    const es = [work(at('2026-11-19', '06:00'), at('2026-11-19', '17:00'), 'Driving'), work(at('2026-11-20', '06:00'), at('2026-11-20', '07:00'), 'Driving')];
    expect(hosClocks(es, at('2026-11-20', '07:00')).drive / H).toBe(10);
  });
  it('adds up 70 hours over 8 days, and a 34-hour break restarts the week', () => {
    const days = ['2026-11-13', '2026-11-14', '2026-11-15', '2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19'];
    const es = days.map(d => work(at(d, '06:00'), at(d, '16:00')));
    expect(hosClocks(es, at('2026-11-19', '16:00')).cycle / H).toBe(0);
    // Two days off (well over 34 hours) and the count starts again.
    const after = [...es, work(at('2026-11-22', '06:00'), at('2026-11-22', '08:00'))];
    expect(hosClocks(after, at('2026-11-22', '08:00')).cycle / H).toBe(68);
  });
});

describe('step times on the LD tab', () => {
  const now = at('2026-11-26', '08:19') + 14000;
  it('treats a time a little ahead as now', () => {
    expect(stepAt('08:30', z, now, at('2026-11-26', '08:00'))).toBe(now + 55000);
  });
  it('still lands after a step saved a little ahead (the reported bug)', () => {
    const drive = at('2026-11-26', '08:20');
    const t = stepAt('08:21', z, now, drive);
    expect(t).toBeGreaterThan(drive);
    expect(t).toBeLessThanOrEqual(now + 60000);
  });
  it('names the start time when the pick is too early', () => {
    expect(() => stepAt('08:19', z, now, at('2026-11-26', '08:20'))).toThrow(/8:20 AM/);
  });
  it('reads a time well ahead as last night', () => {
    expect(stepAt('23:00', z, now)).toBe(at('2026-11-25', '23:00'));
    expect(() => stepAt('23:00', z, now, at('2026-11-26', '07:00'))).toThrow(/hasn't happened yet/);
  });
});

describe('editing a shift that runs past midnight', () => {
  const night = () => toEntries(steps('2026-11-20', [['20:00', 'pretrip', PRESTON], ['20:15', 'drive', PRESTON], ['01:00', 'posttrip', 'Boise'], ['01:15', 'clockout', 'Boise']]));
  it('takes the part after midnight along with the day it started', () => {
    const es = night();
    expect(shiftOf(es, '2026-11-20', z)).toEqual({ day: '2026-11-20', entries: es });
  });
  it('sends the next day, if that is all it holds, back to the shift it belongs to', () => {
    const es = night();
    expect(shiftOf(es, '2026-11-21', z)).toEqual({ day: '2026-11-20', entries: es });
  });
  it('keeps the next day\'s own shift separate from last night\'s tail', () => {
    const es = [...night(), ...toEntries(steps('2026-11-21', [['09:00', 'pretrip', 'Boise'], ['09:15', 'drive', 'Boise'], ['12:00', 'clockout', 'Twin Falls']]))];
    const own = shiftOf(es, '2026-11-21', z);
    expect(own.day).toBe('2026-11-21');
    expect(own.entries.map(e => e.status)).toEqual(['On duty', 'Driving']);
  });
  it('ignores an open entry and empty days', () => {
    expect(shiftOf([], '2026-11-20', z).entries).toEqual([]);
    const open: Entry = { ...work(at('2026-11-20', '07:00'), 0), end: null };
    expect(shiftOf([open], '2026-11-20', z).entries).toEqual([]);
  });
});
