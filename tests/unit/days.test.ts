import { describe, expect, it } from 'vitest';
import { findCity, planSimpleDay, readSimpleDay, planLdDay, readLdDay, place, cityNames, type SimpleDay, type LdDay } from '../../lib/simple-day';
import { validateLog, initialLog, dayKey, epoch, localInput, overlaps, type Entry } from '../../lib/log';

const z = 'America/Los_Angeles';
const simple = (over: Partial<SimpleDay> = {}): SimpleDay => ({ date: '2026-11-17', office: 'Preston', jobs: [{ load: 'Issaquah', unload: 'Seattle' }], clockIn: '07:45', clockOut: '16:00', lunch: 30, miles: null, ...over });
const ld = (over: Partial<LdDay> = {}): LdDay => ({ date: '2026-11-17', start: { at: 'office', office: 'Preston', hotel: '' }, unload: null, end: { at: 'hotel', office: 'Preston', hotel: 'Spokane' }, clockIn: '07:00', clockOut: '17:00', lunch: 30, miles: null, ...over });
const span = (es: Entry[]) => [localInput(es[0].start, z).slice(11), localInput(es.at(-1)!.end!, z).slice(11)];

describe('city list', () => {
  it('has no duplicate names', () => {
    expect(new Set(cityNames.map(c => c.toLowerCase())).size).toBe(cityNames.length);
  });
  it('finds cities from names, addresses and prefixes', () => {
    expect(findCity('issaquah')?.name).toBe('Issaquah');
    expect(findCity('123 Main St, Kent, WA 98032')?.name).toBe('Kent');
    expect(findCity('issaq')?.name).toBe('Issaquah');
    expect(findCity('Issaquah High')?.name).toBe('Issaquah Highlands');
    expect(findCity('Coeur dAlene, ID 83814')?.name).toBe("Coeur d'Alene");
    expect(findCity('Bell')).toBeNull(); // Bellevue, Bellingham, Belltown
    expect(findCity('ab')).toBeNull();
    expect(findCity('')).toBeNull();
  });
  it('labels the state', () => {
    expect(place({ name: 'Portland' })).toBe('Portland, OR');
    expect(place({ name: 'Boise' })).toBe('Boise, ID');
    expect(place({ name: 'Magnolia' })).toBe('Magnolia, WA');
  });
});

describe('Simple day', () => {
  it('lays out the shift from clock in to clock out', () => {
    const p = planSimpleDay(simple(), z);
    expect(span(p.entries)).toEqual(['07:45', '16:00']);
    expect(p.entries.filter(e => e.note === 'Lunch break')).toHaveLength(1);
    expect(() => validateLog({ ...initialLog(), entries: p.entries })).not.toThrow();
    for (let i = 1; i < p.entries.length; i++) expect(p.entries[i].start).toBe(p.entries[i - 1].end);
  });
  it('reads a saved day back for editing', () => {
    const day = simple({ jobs: [{ load: 'Renton', unload: 'Bellevue' }, { load: 'Kirkland', unload: 'Redmond' }], lunch: 45, clockOut: '17:30' });
    expect(readSimpleDay(planSimpleDay(day, z).entries, z)).toEqual(day);
  });
  it('keeps odometer miles exactly', () => {
    const p = planSimpleDay(simple({ miles: 61.3 }), z);
    expect(p.miles).toBe(61.3);
    expect(readSimpleDay(p.entries, z)?.miles).toBe(61.3);
  });
  it('still opens an old Kent day', () => {
    const day = simple({ office: 'Kent' });
    expect(readSimpleDay(planSimpleDay(day, z).entries, z)?.office).toBe('Kent');
  });
  it('plans a single-location (labor only) job: drive there, work, drive back', () => {
    const day = simple({ jobs: [{ load: 'Bellevue', unload: '', single: true }] });
    const p = planSimpleDay(day, z);
    expect(span(p.entries)).toEqual(['07:45', '16:00']);
    const drives = p.entries.filter(e => e.status === 'Driving');
    expect(drives.map(e => e.note)).toEqual(['To job site', 'Return to office']);
    expect(drives[0].to).toBe('Bellevue, WA');
    expect(p.entries.some(e => e.note.startsWith('Labor, single location') && e.from === 'Bellevue, WA')).toBe(true);
    expect(p.entries.some(e => /^(Loading|Unloading)/.test(e.note))).toBe(false);
    expect(readSimpleDay(p.entries, z)).toEqual(day);
  });
  it('mixes a single-location job with a regular one', () => {
    const day = simple({ jobs: [{ load: 'Renton', unload: 'Bellevue' }, { load: 'Kirkland', unload: '', single: true }], clockOut: '17:00' });
    const p = planSimpleDay(day, z);
    expect(p.entries.filter(e => e.status === 'Driving').map(e => e.note)).toEqual(['To load (job 1)', 'To unload (job 1)', 'To job site (job 2)', 'Return to office']);
    expect(() => validateLog({ ...initialLog(), entries: p.entries })).not.toThrow();
    expect(readSimpleDay(p.entries, z)).toEqual(day);
    expect(() => planSimpleDay(simple({ jobs: [{ load: '', unload: '', single: true }] }), z)).toThrow(/city of the job/);
  });
  it('explains what is wrong', () => {
    expect(() => planSimpleDay(simple({ jobs: [{ load: 'Issaquah', unload: '' }] }), z)).toThrow(/load city and an unload city/);
    expect(() => planSimpleDay(simple({ clockOut: '07:00' }), z)).toThrow(/after clock in/);
    expect(() => planSimpleDay(simple({ jobs: [{ load: 'Nowhereville', unload: 'Seattle' }] }), z)).toThrow(/Couldn't find/);
    expect(planSimpleDay(simple({ jobs: [{ load: 'Nowhereville', unload: 'Seattle' }], miles: 40 }), z).miles).toBe(40);
    expect(() => planSimpleDay(simple({ clockOut: '08:15' }), z)).toThrow(/too short|Lunch is longer/);
  });
});

describe('LD estimate', () => {
  it('plans office to hotel and reads it back', () => {
    const day = ld();
    const p = planLdDay(day, z);
    expect(span(p.entries)).toEqual(['07:00', '17:00']);
    expect(readLdDay(p.entries, z)).toEqual(day);
  });
  it('plans hotel → unload → office', () => {
    const day = ld({ start: { at: 'hotel', office: 'Preston', hotel: 'Spokane' }, unload: 'Yakima', end: { at: 'office', office: 'Preston', hotel: '' } });
    expect(readLdDay(planLdDay(day, z).entries, z)).toEqual(day);
  });
  it('sends office to office to Simple day', () => {
    expect(() => planLdDay(ld({ end: { at: 'office', office: 'Preston', hotel: '' } }), z)).toThrow(/Simple day/);
  });
});

describe('saving', () => {
  const e = (start: number, end: number | null): Entry => ({ id: crypto.randomUUID(), status: 'On duty', start, end, from: '', to: '', miles: null, note: '', partial: false, source: 'manual' });
  it('rejects overlapping periods and bad times', () => {
    expect(() => validateLog({ ...initialLog(), entries: [e(0, 120000), e(60000, 90000)] })).toThrow(/overlap/);
    expect(() => validateLog({ ...initialLog(), entries: [e(100000, 50000)] })).toThrow(/after start/);
    expect(() => validateLog({ ...initialLog(), entries: [e(0, Date.now() + 5 * 60000)] })).toThrow(/future/);
    expect(overlaps(e(0, 10), e(10, 20))).toBe(false);
  });
  it('allows an open entry that started up to a minute ahead', () => {
    expect(() => validateLog({ ...initialLog(), active: e(Date.now() + 55000, null) })).not.toThrow();
  });
  it('uses the home-terminal day, not the phone\'s', () => {
    // 11:30 PM in Seattle is already the next day in UTC.
    expect(dayKey(epoch('2026-11-20T23:30', z), z)).toBe('2026-11-20');
  });
});
