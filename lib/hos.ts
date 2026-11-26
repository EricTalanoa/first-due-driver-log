import { bounds, epoch, localInput, dayKey, type Entry, type Status } from './log';
import { findCity, roadMiles, straightMiles, offices } from './simple-day';

// Hours-of-service helpers: what each tap in the LD flow means, the filled-in 24-hour chart,
// and the federal limits for property-carrying drivers (49 CFR 395.3).

/** What a driver can say they are doing. Each one maps to a duty status line on the chart. */
export const activities = {
  pretrip: { label: 'Pre-trip inspection', status: 'On duty', note: 'Pre-trip inspection' },
  drive: { label: 'Driving', status: 'Driving', note: 'Driving' },
  fuel: { label: 'Fuel stop', status: 'On duty', note: 'Fueling' },
  break: { label: 'Quick break', status: 'Off duty', note: 'Quick break' },
  lunch: { label: 'Lunch (30 min)', status: 'Off duty', note: 'Lunch break' },
  load: { label: 'Start loading', status: 'On duty', note: 'Loading' },
  unload: { label: 'Start unload', status: 'On duty', note: 'Unloading' },
  work: { label: 'Other work', status: 'On duty', note: 'Other work' },
  riding: { label: 'Switch drivers', status: 'On duty', note: 'Riding – co-driver driving' },
  posttrip: { label: 'Post-trip inspection', status: 'On duty', note: 'Post-trip inspection' },
  off: { label: 'Off duty', status: 'Off duty', note: 'Off duty' },
} as const satisfies Record<string, { label: string; status: Status; note: string }>;
export type Activity = keyof typeof activities;

/** Works out which activity an entry was, from its note (or its status for older entries). */
export function activityOf(e: Pick<Entry, 'status' | 'note'>): Activity {
  const note = e.note.split(' | ')[0].trim().toLowerCase();
  for (const [k, a] of Object.entries(activities) as [Activity, (typeof activities)[Activity]][]) if (a.status === e.status && note.startsWith(a.note.toLowerCase())) return k;
  if (e.status === 'Driving') return 'drive';
  if (/unload/.test(note)) return 'unload';
  if (/load/.test(note)) return 'load';
  if (/pre-trip/.test(note)) return 'pretrip';
  if (/post-trip/.test(note)) return 'posttrip';
  if (/lunch/.test(note)) return 'lunch';
  return e.status === 'Off duty' || e.status === 'Sleeper berth' ? 'off' : 'work';
}

/** The choices to offer next, given what the driver is doing now. `null` = off the clock. */
export function nextSteps(now: Activity | null): (Activity | 'clockout')[] {
  if (now === null) return ['pretrip'];
  if (now === 'drive') return ['fuel', 'break', 'lunch', 'unload', 'load', 'riding', 'posttrip', 'work'];
  if (now === 'riding') return ['drive', 'fuel', 'break', 'lunch', 'unload', 'load', 'posttrip'];
  if (now === 'posttrip') return ['clockout', 'drive', 'work'];
  if (now === 'break' || now === 'lunch' || now === 'off') return ['drive', 'work', 'unload', 'posttrip', 'clockout'];
  return ['drive', 'break', 'lunch', 'posttrip', 'clockout'];
}

export const PRESTON = offices.Preston.label;
const HOTEL = 'Hotel – ';
/** The city behind a place label: an office, "Hotel – Spokane, WA", or a typed address. */
export function cityOf(place: string) {
  const office = Object.values(offices).find(o => o.label === place);
  if (office) return office;
  return findCity(place.startsWith(HOTEL) ? place.slice(HOTEL.length) : place);
}
/** Estimated road miles between two places, or null if either city is unknown. */
export function estimateMiles(from: string, to: string) {
  const a = cityOf(from), b = cityOf(to);
  return a && b ? Math.round(roadMiles(a, b) * 10) / 10 : null;
}
/** Marks the first entry of a day logged on the LD tab, so History can group LD days. */
export const LD_MARK = ' | LD trip';
/**
 * Whether a day was long distance: logged on the LD tab or with the LD estimate, a hotel stop,
 * or a place more than 150 air-miles from the Preston office (the short-haul limit).
 */
export function isLdDay(es: Entry[]) {
  return es.some(e => /\bLD\b/.test(e.note) || [e.from, e.to].some(p => p.startsWith(HOTEL) || far(p)));
}
const far = (p: string) => { const c = p ? cityOf(p) : null; return !!c && straightMiles(c, offices.Preston) > 150; };
export const hotel = (city: string) => (city.startsWith(HOTEL) ? city : HOTEL + city);

// ---- Timeline: the day as a list of status changes, for filling in or fixing a day ----

export type Step = { id: string; time: number; act: Activity | 'clockout'; place: string; miles: number | null };

/** Reads a day's entries as status changes. Gaps between entries become Off duty steps. */
export function toSteps(entries: Entry[]): Step[] {
  const es = [...entries].sort((a, b) => a.start - b.start);
  const steps: Step[] = [];
  es.forEach((e, i) => {
    const act = activityOf(e);
    steps.push({ id: e.id, time: e.start, act, place: e.from, miles: act === 'drive' ? e.miles : null });
    const next = es[i + 1];
    if (e.end !== null && (!next || next.start > e.end)) steps.push({ id: crypto.randomUUID(), time: e.end, act: next ? 'break' : 'clockout', place: e.to || e.from, miles: null });
  });
  return steps;
}

/** Turns status changes back into entries. Each step runs until the next one; the last must be Clock out. */
export function toEntries(steps: Step[], tag = ''): Entry[] {
  if (!steps.length) throw new Error('Add your clock-in first.');
  if (steps[steps.length - 1].act !== 'clockout') throw new Error('End the day with Clock out.');
  for (let i = 1; i < steps.length; i++) if (steps[i].time <= steps[i - 1].time) throw new Error(`Step ${i + 1} must be after step ${i}. Check the times.`);
  const out: Entry[] = [];
  for (let i = 0; i < steps.length - 1; i++) {
    const s = steps[i], n = steps[i + 1];
    if (s.act === 'clockout') continue;
    const a = activities[s.act], drive = s.act === 'drive';
    out.push({ id: s.id, status: a.status, start: s.time, end: n.time, from: s.place.trim(), to: drive ? n.place.trim() : '', miles: drive ? s.miles ?? estimateMiles(s.place, n.place) : null, note: a.note, partial: false, source: 'manual' });
  }
  if (tag && out.length && !out[0].note.includes(tag)) out[0].note += tag;
  return out;
}

/** Interprets "HH:MM" on `day`; a time earlier than `after` rolls onto the next day (past midnight). */
export function stepTime(day: string, hhmm: string, zone: string, after?: number) {
  let t = epoch(`${day}T${hhmm}`, zone);
  while (after !== undefined && t <= after) t = epoch(`${dayKey(t + 86400000, zone)}T${hhmm}`, zone);
  return t;
}
export const hhmm = (t: number, zone: string) => localInput(t, zone).slice(11);

/**
 * The moment a live LD step happened, from the "HH:MM" the driver picked. Drivers round up, so a time up to
 * 15 minutes ahead means "now"; a time further ahead means last night. `after` is when the current step started.
 */
export function stepAt(time: string, zone: string, now: number, after?: number) {
  const label = (t: number) => new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', minute: '2-digit' }).format(t);
  let at = epoch(`${dayKey(now, zone)}T${time}`, zone);
  if (at > now) {
    // Can't save a start in the future, but it must still land after the current step (which may itself be a little ahead).
    if (at - now <= 15 * 60000) at = after !== undefined && at > after ? Math.max(Math.min(at, now + 55000), after + 1000) : Math.min(at, now + 55000);
    else {
      const night = epoch(`${dayKey(now - 86400000, zone)}T${time}`, zone);
      if (after !== undefined && night <= after) throw new Error(`${label(at)} hasn't happened yet. It's ${label(now)} now.`);
      at = night;
    }
  }
  if (after !== undefined && at <= after) throw new Error(`What you're doing now started at ${label(after)}. Pick a time after that.`);
  return at;
}

// ---- The 24-hour chart ----

export type Segment = { status: Status; start: number; end: number; filled: boolean; entry?: Entry };

/**
 * The day's line on the chart, midnight to midnight (or to `now` for today). Time with no entry is
 * Off duty, as on a paper log: before clock-in, after clock-out and between entries.
 */
export function chartSegments(entries: Entry[], day: string, zone: string, now: number): { segments: Segment[]; start: number; end: number; upto: number } {
  const [start, end] = bounds(day, zone);
  const upto = Math.min(end, Math.max(start, now));
  const rows = entries.filter(e => e.start < upto && (e.end ?? now) > start).sort((a, b) => a.start - b.start);
  const segments: Segment[] = [];
  let t = start;
  for (const e of rows) {
    const s = Math.max(start, e.start), f = Math.min(upto, e.end ?? now);
    if (s > t) segments.push({ status: 'Off duty', start: t, end: s, filled: true });
    if (f > Math.max(s, t)) segments.push({ status: e.status, start: Math.max(s, t), end: f, filled: false, entry: e });
    t = Math.max(t, f);
  }
  if (upto > t) segments.push({ status: 'Off duty', start: t, end: upto, filled: true });
  return { segments, start, end, upto };
}

// ---- Hours-of-service clocks ----

const H = 3600000;
export type Clocks = { drive: number; window: number; breakDue: number; cycle: number; shiftStart: number | null };

/**
 * Time left under each limit right now: 11 hours driving and a 14-hour window after 10 hours off,
 * a 30-minute break after 8 hours of driving, and 70 hours on duty in 8 days (reset by 34 hours off).
 * Time with no entry counts as off duty.
 */
export function hosClocks(entries: Entry[], now: number): Clocks {
  const recent = entries.filter(e => e.start < now && (e.end ?? now) > now - 10 * 24 * H).map(e => ({ ...e, end: e.end ?? now })).sort((a, b) => a.start - b.start);
  const work = recent.filter(e => e.status === 'Driving' || e.status === 'On duty');
  // Walk the work in order; a long enough gap starts a new shift (10 h) or a new 8-day cycle (34 h).
  let shiftStart: number | null = null, cycleStart = now - 8 * 24 * H, lastEnd = -Infinity;
  for (const w of work) {
    const gap = w.start - lastEnd;
    if (gap >= 10 * H) shiftStart = w.start;
    if (gap >= 34 * H) cycleStart = Math.max(cycleStart, w.start);
    lastEnd = Math.max(lastEnd, w.end);
  }
  if (now - lastEnd >= 10 * H) shiftStart = null;
  const inRange = (e: { start: number; end: number }, from: number) => Math.max(0, Math.min(e.end, now) - Math.max(e.start, from));
  const driving = shiftStart === null ? 0 : work.filter(e => e.status === 'Driving').reduce((n, e) => n + inRange(e, shiftStart!), 0);
  // Driving since the last 30 minutes in a row not driving.
  let sinceBreak = 0, lastDriveEnd = -Infinity;
  for (const e of recent) {
    if (e.status !== 'Driving') continue;
    if (e.start - lastDriveEnd >= 0.5 * H) sinceBreak = 0;
    sinceBreak += e.end - e.start;
    lastDriveEnd = e.end;
  }
  if (now - lastDriveEnd >= 0.5 * H) sinceBreak = 0;
  const cycle = work.reduce((n, e) => n + inRange(e, cycleStart), 0);
  return {
    shiftStart,
    drive: 11 * H - driving,
    window: shiftStart === null ? 14 * H : 14 * H - (now - shiftStart),
    breakDue: 8 * H - sinceBreak,
    cycle: 70 * H - cycle,
  };
}
