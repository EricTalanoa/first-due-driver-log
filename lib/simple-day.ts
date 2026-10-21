import { epoch, dayKey, localInput, type Entry } from './log';

// Plans a whole work day from a few answers: office -> load city -> unload city -> office.
// Distances are straight-line estimates scaled for roads; there is no live routing.

export const offices = {
  Preston: { label: 'Preston office – 8126 304th Ave SE, Preston, WA 98050', lat: 47.5235, lon: -121.929 },
  Kent: { label: 'Kent office – 21854 76th Ave S, Kent, WA 98032', lat: 47.4005, lon: -122.2405 },
} as const;
export type Office = keyof typeof offices;

const raw = `Seattle 47.6062 -122.3321|Ballard 47.6687 -122.3843|West Seattle 47.5667 -122.3868|Queen Anne 47.6374 -122.3571|Capitol Hill 47.6253 -122.3222|Fremont 47.651 -122.35|Greenwood 47.6907 -122.3553|Northgate 47.7062 -122.3255|Lake City 47.7193 -122.295|University District 47.6614 -122.3133|Georgetown 47.5487 -122.3214|Rainier Beach 47.5126 -122.267|Bellevue 47.6101 -122.2015|Factoria 47.5779 -122.1696|Totem Lake 47.7134 -122.1857|Redmond 47.674 -122.1215|Kirkland 47.6769 -122.206|Bothell 47.7601 -122.2054|Woodinville 47.7543 -122.1635|Issaquah 47.5301 -122.0326|Sammamish 47.6163 -122.0356|Preston 47.5215 -121.9318|Fall City 47.5673 -121.8887|Snoqualmie 47.5287 -121.8254|North Bend 47.4957 -121.7868|Carnation 47.6479 -121.914|Duvall 47.7423 -121.9857|Monroe 47.8554 -121.9709|Sultan 47.8626 -121.8165|Gold Bar 47.8568 -121.697|Snohomish 47.9129 -122.0982|Mill Creek 47.8601 -122.2043|Lynnwood 47.8209 -122.3151|Edmonds 47.8107 -122.3774|Mountlake Terrace 47.7882 -122.3087|Brier 47.7845 -122.274|Shoreline 47.7557 -122.3415|Lake Forest Park 47.7568 -122.2807|Kenmore 47.7573 -122.244|Mukilteo 47.9445 -122.3046|Everett 47.979 -122.2021|Marysville 48.0518 -122.1771|Lake Stevens 48.0151 -122.064|Granite Falls 48.084 -121.9687|Arlington 48.1987 -122.1251|Stanwood 48.2412 -122.3707|Mount Vernon 48.4212 -122.3341|Burlington 48.4757 -122.3254|Anacortes 48.5126 -122.6127|Oak Harbor 48.2932 -122.6432|Bellingham 48.7519 -122.4787|Ferndale 48.8465 -122.591|Lynden 48.9465 -122.4521|Blaine 48.9937 -122.7471|Renton 47.4829 -122.2171|Newcastle 47.5301 -122.1557|Mercer Island 47.5707 -122.2221|Medina 47.6204 -122.2279|Tukwila 47.474 -122.261|SeaTac 47.4436 -122.2961|Burien 47.4704 -122.3468|Normandy Park 47.4362 -122.3407|Des Moines 47.4018 -122.3243|Kent 47.3809 -122.2348|Covington 47.3582 -122.1224|Maple Valley 47.3926 -122.0465|Hobart 47.4229 -121.969|Ravensdale 47.3526 -121.9837|Black Diamond 47.3087 -122.0032|Enumclaw 47.2043 -121.9915|Auburn 47.3073 -122.2285|Federal Way 47.3223 -122.3126|Algona 47.2793 -122.2507|Pacific 47.2643 -122.2501|Edgewood 47.2501 -122.2937|Sumner 47.2032 -122.2404|Bonney Lake 47.1771 -122.1868|Buckley 47.1632 -122.0268|Puyallup 47.1854 -122.2929|Fife 47.2393 -122.3571|Milton 47.2482 -122.3132|Tacoma 47.2529 -122.4443|University Place 47.2357 -122.5501|Steilacoom 47.1698 -122.6029|Lakewood 47.1718 -122.5185|Gig Harbor 47.3293 -122.5801|Spanaway 47.104 -122.4346|Graham 47.0529 -122.2943|Orting 47.0979 -122.2043|DuPont 47.0971 -122.6315|Olympia 47.0379 -122.9007|Lacey 47.0343 -122.8232|Tumwater 47.0073 -122.9093|Yelm 46.9421 -122.6059|Shelton 47.2151 -123.1007|Centralia 46.7162 -122.9543|Chehalis 46.662 -122.964|Bremerton 47.5673 -122.6326|Silverdale 47.6446 -122.6949|Poulsbo 47.736 -122.6465|Port Orchard 47.5404 -122.6363|Bainbridge Island 47.6262 -122.5212|Kingston 47.7987 -122.4982|Vashon 47.4473 -122.4598|Port Townsend 48.117 -122.7604|Sequim 48.0795 -123.1018|Port Angeles 48.1181 -123.4307|Aberdeen 46.9754 -123.8157|Cle Elum 47.1954 -120.9392|Ellensburg 46.9965 -120.5478|Wenatchee 47.4235 -120.3103|Leavenworth 47.5962 -120.6615|Yakima 46.6021 -120.5059|Moses Lake 47.1301 -119.2781|Richland 46.2857 -119.2845|Kennewick 46.2112 -119.1372|Pasco 46.2396 -119.1006|Walla Walla 46.0646 -118.343|Spokane 47.6588 -117.426|Spokane Valley 47.6732 -117.2394|Longview 46.1382 -122.9382|Kelso 46.1468 -122.9084|Ridgefield 45.8151 -122.7426|Battle Ground 45.7807 -122.5334|Vancouver 45.6387 -122.6615|Camas 45.5871 -122.3995|Portland 45.5152 -122.6784|Gresham 45.4982 -122.4318|Beaverton 45.4871 -122.8037|Hillsboro 45.5229 -122.9898|Lake Oswego 45.4207 -122.6706|Hood River 45.7054 -121.5215|Salem 44.9429 -123.0351|Bend 44.0582 -121.3153|Eugene 44.0521 -123.0868`;

export const cities: Record<string, { name: string; lat: number; lon: number }> = Object.fromEntries(
  raw.split('|').map(row => { const p = row.split(' '); const lon = Number(p.pop()), lat = Number(p.pop()); const name = p.join(' '); return [key(name), { name, lat, lon }]; }),
);
export const cityNames = Object.values(cities).map(c => c.name).sort();

function key(s: string) { return s.toLowerCase().replace(/\./g, '').replace(/\s+/g, ' ').trim(); }

/** Finds a city from free text like "issaquah", "Issaquah, WA" or "123 Main St, Kent, WA 98032". */
export function findCity(input: string) {
  const parts = input.split(',').map(p => key(p.replace(/\b(wa|or|washington|oregon)\b/gi, '').replace(/\d{5}(-\d{4})?/, ''))).filter(Boolean);
  for (const p of [...parts].reverse()) if (cities[p]) return cities[p];
  const whole = key(input);
  const hit = Object.keys(cities).filter(k => k.startsWith(whole));
  return whole.length >= 3 && hit.length === 1 ? cities[hit[0]] : null;
}

function straightMiles(a: { lat: number; lon: number }, b: { lat: number; lon: number }) {
  const r = Math.PI / 180, dl = (b.lat - a.lat) * r, dn = (b.lon - a.lon) * r;
  const h = Math.sin(dl / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dn / 2) ** 2;
  return 3958.76 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}
/** Road miles: straight line times a winding factor; at least half a mile for a same-city hop. */
export function roadMiles(a: { lat: number; lon: number }, b: { lat: number; lon: number }) {
  const m = straightMiles(a, b);
  return Math.max(0.5, m * (m > 60 ? 1.25 : 1.35));
}
/** Minutes behind the wheel for a leg: slower average speeds on short local hops. */
export function driveMinutes(mi: number) {
  const mph = mi < 3 ? 22 : mi < 12 ? 30 : mi < 40 ? 40 : 52;
  return Math.round((mi / mph) * 60) + 3;
}

const oregon = /^(Portland|Gresham|Beaverton|Hillsboro|Lake Oswego|Hood River|Salem|Bend|Eugene)$/;
/** "Issaquah, WA" style label for a known city. */
export function place(c: { name: string }) { return `${c.name}, ${oregon.test(c.name) ? 'OR' : 'WA'}`; }

/** Closest known city to a GPS point, if one is within range. */
export function nearestCity(p: { lat: number; lon: number }, maxMiles = 8) {
  let best: { name: string; lat: number; lon: number } | null = null, dist = maxMiles;
  for (const c of Object.values(cities)) { const m = straightMiles(p, c); if (m < dist) { best = c; dist = m; } }
  return best;
}

export type Job = { load: string; unload: string };
export type SimpleDay = { date: string; office: Office; jobs: Job[]; clockIn: string; clockOut: string; lunch: number; miles?: number | null };
export type Plan = { entries: Entry[]; miles: number; driveMin: number; unknown: string[]; route: string[] };

const SIMPLE_TAG = 'Simple day entry';
const jobTag = (n: number, total: number) => (total > 1 ? ` (job ${n})` : '');

/**
 * Lays out a day: pre-trip, then for each job drive to load, load, drive to unload, unload;
 * drive back, post-trip. Lunch goes in whichever stop is nearest the middle of the shift.
 */
export function planSimpleDay(d: SimpleDay, zone: string, newId: () => string = () => crypto.randomUUID()): Plan {
  const office = offices[d.office];
  const jobs = d.jobs.map(j => ({ load: j.load.trim(), unload: j.unload.trim() })).filter(j => j.load || j.unload);
  if (!jobs.length || jobs.some(j => !j.load || !j.unload)) throw new Error(d.jobs.length > 1 ? 'Enter a load city and an unload city for each job.' : 'Enter both a load city and an unload city.');
  const stops = jobs.flatMap((j, n) => [
    { text: j.load, city: findCity(j.load), work: `Loading${jobTag(n + 1, jobs.length)}`, drive: `To load${jobTag(n + 1, jobs.length)}` },
    { text: j.unload, city: findCity(j.unload), work: `Unloading${jobTag(n + 1, jobs.length)}`, drive: `To unload${jobTag(n + 1, jobs.length)}` },
  ]);
  const unknown = [...new Set(stops.filter(s => !s.city).map(s => s.text))];
  const t0 = epoch(`${d.date}T${d.clockIn}`, zone), t1 = epoch(`${d.date}T${d.clockOut}`, zone);
  if (t1 <= t0) throw new Error('Clock out must be after clock in.');
  const span = Math.round((t1 - t0) / 60000), lunch = Math.max(0, Math.round(d.lunch));
  if (lunch >= span) throw new Error('Lunch is longer than the whole shift.');

  const points = [office, ...stops.map(s => s.city), office];
  let legs: number[];
  if (!unknown.length) legs = points.slice(1).map((p, i) => roadMiles(points[i]!, p!));
  else if (d.miles && d.miles > 0) legs = points.slice(1).map(() => d.miles! / (points.length - 1));
  else throw new Error(`Couldn't find ${unknown.map(u => `“${u}”`).join(' or ')}. Pick a city from the list, or enter the day's total miles.`);
  if (d.miles && d.miles > 0 && !unknown.length) { const est = legs.reduce((a, b) => a + b, 0); legs = legs.map(m => (m * d.miles!) / est); }
  legs = legs.map(m => Math.round(m * 10) / 10);
  // Rounding each leg can drift from the odometer total; settle the difference on the last leg.
  if (d.miles && d.miles > 0) legs[legs.length - 1] = Math.max(0, Math.round((d.miles - legs.slice(0, -1).reduce((a, b) => a + b, 0)) * 10) / 10);

  const pre = 15, post = 10, minSite = 20;
  let drive = legs.map(driveMinutes);
  const room = span - lunch - pre - post - stops.length * minSite;
  if (room <= 0) throw new Error('That shift is too short to fit the drives and stops. Use Advanced for this day.');
  const driveTotal = drive.reduce((a, b) => a + b, 0);
  if (driveTotal > room) drive = drive.map(m => Math.max(4, Math.floor((m * room) / driveTotal)));
  const site = span - lunch - pre - post - drive.reduce((a, b) => a + b, 0);
  const atStop = stops.map((_, i) => Math.floor(site / stops.length) + (i >= stops.length - (site % stops.length) ? 1 : 0));

  // Pick where lunch goes: the stop closest to the middle of the working time, the later one on a tie.
  const target = Math.round((span - lunch) / 2);
  let lunchAt = { stop: -1, after: 0 }, gap = Infinity;
  for (let i = 0, m = pre; i < stops.length; i++) {
    m += drive[i];
    const into = Math.min(Math.max(target - m, 0), atStop[i]), off = Math.abs(target - (m + into));
    if (off <= gap) { gap = off; lunchAt = { stop: i, after: into }; }
    m += atStop[i];
  }

  const names = [office.label, ...stops.map(s => (s.city ? place(s.city) : s.text))];
  const entries: Entry[] = [];
  let t = t0;
  const add = (status: Entry['status'], min: number, from: string, to = '', miles: number | null = null, note = '') => {
    if (min <= 0) return;
    const end = t + min * 60000;
    entries.push({ id: newId(), status, start: t, end, from, to, miles, note, partial: false, source: 'manual' });
    t = end;
  };
  add('On duty', pre, names[0], '', null, 'Pre-trip inspection / prep at office');
  stops.forEach((s, i) => {
    add('Driving', drive[i], names[i], names[i + 1], legs[i], s.drive);
    if (lunch && lunchAt.stop === i) {
      add('On duty', lunchAt.after, names[i + 1], '', null, s.work);
      add('Off duty', lunch, names[i + 1], '', null, 'Lunch break');
      add('On duty', atStop[i] - lunchAt.after, names[i + 1], '', null, s.work);
    } else add('On duty', atStop[i], names[i + 1], '', null, s.work);
  });
  add('Driving', drive[stops.length], names[stops.length], names[0], legs[stops.length], 'Return to office');
  add('On duty', Math.round((t1 - t) / 60000), names[0], '', null, 'Post-trip / unload equipment at office');
  entries[0].note += ` | ${SIMPLE_TAG}: drive times and miles estimated from cities.`;
  const route = [d.office, ...stops.map(s => (s.city ? s.city.name : s.text)), 'back'];
  return { entries, miles: Math.round(legs.reduce((a, b) => a + b, 0) * 10) / 10, driveMin: drive.reduce((a, b) => a + b, 0), unknown, route };
}

/** Rebuilds the Simple day answers from entries it created earlier, so the day can be edited. */
export function readSimpleDay(entries: Entry[], zone: string): SimpleDay | null {
  const es = [...entries].sort((a, b) => a.start - b.start);
  if (!es.length || !es[0].note.includes(SIMPLE_TAG) || es.some(e => e.end === null)) return null;
  const office = (Object.keys(offices) as Office[]).find(o => offices[o].label === es[0].from);
  if (!office) return null;
  const city = (s: string) => s.replace(/, (WA|OR)$/, '');
  const jobs: Job[] = [];
  for (const e of es) {
    if (e.status !== 'Driving') continue;
    if (e.note.startsWith('To load')) jobs.push({ load: city(e.to), unload: '' });
    else if (e.note.startsWith('To unload') && jobs.length) jobs[jobs.length - 1].unload = city(e.to);
  }
  if (!jobs.length || jobs.some(j => !j.unload)) return null;
  const lunch = es.filter(e => e.status === 'Off duty' && e.note === 'Lunch break').reduce((n, e) => n + (e.end! - e.start) / 60000, 0);
  const day: SimpleDay = { date: dayKey(es[0].start, zone), office, jobs, clockIn: localInput(es[0].start, zone).slice(11), clockOut: localInput(es[es.length - 1].end!, zone).slice(11), lunch: Math.round(lunch), miles: null };
  // If the saved miles differ from the city estimate, the driver typed odometer miles; keep them.
  const saved = Math.round(es.reduce((n, e) => n + (e.status === 'Driving' ? e.miles ?? 0 : 0), 0) * 10) / 10;
  try { if (Math.abs(planSimpleDay(day, zone, () => '').miles - saved) > 0.15) day.miles = saved; } catch { day.miles = saved; }
  return day;
}
