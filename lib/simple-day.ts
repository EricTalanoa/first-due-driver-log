import { epoch, dayKey, localInput, type Entry } from './log';

// Plans a whole work day from a few answers: office -> load city -> unload city -> office.
// Distances are straight-line estimates scaled for roads; there is no live routing.

export const offices = {
  Preston: { label: 'Preston office – 8126 304th Ave SE, Preston, WA 98050', lat: 47.5235, lon: -121.929 },
  Kent: { label: 'Kent office – 21854 76th Ave S, Kent, WA 98032', lat: 47.4005, lon: -122.2405 },
} as const;
export type Office = keyof typeof offices;
/** Offices drivers can pick today. Kent closed when Preston doubled in size; it stays above so older Kent days still open. */
export const activeOffices: Office[] = ['Preston'];

const raw = `Seattle 47.6062 -122.3321|Ballard 47.6687 -122.3843|West Seattle 47.5667 -122.3868|Queen Anne 47.6374 -122.3571|Capitol Hill 47.6253 -122.3222|Fremont 47.651 -122.35|Greenwood 47.6907 -122.3553|Northgate 47.7062 -122.3255|Lake City 47.7193 -122.295|University District 47.6614 -122.3133|Georgetown 47.5487 -122.3214|Rainier Beach 47.5126 -122.267|Bellevue 47.6101 -122.2015|Factoria 47.5779 -122.1696|Totem Lake 47.7134 -122.1857|Redmond 47.674 -122.1215|Kirkland 47.6769 -122.206|Bothell 47.7601 -122.2054|Woodinville 47.7543 -122.1635|Issaquah 47.5301 -122.0326|Sammamish 47.6163 -122.0356|Preston 47.5215 -121.9318|Fall City 47.5673 -121.8887|Snoqualmie 47.5287 -121.8254|North Bend 47.4957 -121.7868|Carnation 47.6479 -121.914|Duvall 47.7423 -121.9857|Monroe 47.8554 -121.9709|Sultan 47.8626 -121.8165|Gold Bar 47.8568 -121.697|Snohomish 47.9129 -122.0982|Mill Creek 47.8601 -122.2043|Lynnwood 47.8209 -122.3151|Edmonds 47.8107 -122.3774|Mountlake Terrace 47.7882 -122.3087|Brier 47.7845 -122.274|Shoreline 47.7557 -122.3415|Lake Forest Park 47.7568 -122.2807|Kenmore 47.7573 -122.244|Mukilteo 47.9445 -122.3046|Everett 47.979 -122.2021|Marysville 48.0518 -122.1771|Lake Stevens 48.0151 -122.064|Granite Falls 48.084 -121.9687|Arlington 48.1987 -122.1251|Stanwood 48.2412 -122.3707|Mount Vernon 48.4212 -122.3341|Burlington 48.4757 -122.3254|Anacortes 48.5126 -122.6127|Oak Harbor 48.2932 -122.6432|Bellingham 48.7519 -122.4787|Ferndale 48.8465 -122.591|Lynden 48.9465 -122.4521|Blaine 48.9937 -122.7471|Renton 47.4829 -122.2171|Newcastle 47.5301 -122.1557|Mercer Island 47.5707 -122.2221|Medina 47.6204 -122.2279|Tukwila 47.474 -122.261|SeaTac 47.4436 -122.2961|Burien 47.4704 -122.3468|Normandy Park 47.4362 -122.3407|Des Moines 47.4018 -122.3243|Kent 47.3809 -122.2348|Covington 47.3582 -122.1224|Maple Valley 47.3926 -122.0465|Hobart 47.4229 -121.969|Ravensdale 47.3526 -121.9837|Black Diamond 47.3087 -122.0032|Enumclaw 47.2043 -121.9915|Auburn 47.3073 -122.2285|Federal Way 47.3223 -122.3126|Algona 47.2793 -122.2507|Pacific 47.2643 -122.2501|Edgewood 47.2501 -122.2937|Sumner 47.2032 -122.2404|Bonney Lake 47.1771 -122.1868|Buckley 47.1632 -122.0268|Puyallup 47.1854 -122.2929|Fife 47.2393 -122.3571|Milton 47.2482 -122.3132|Tacoma 47.2529 -122.4443|University Place 47.2357 -122.5501|Steilacoom 47.1698 -122.6029|Lakewood 47.1718 -122.5185|Gig Harbor 47.3293 -122.5801|Spanaway 47.104 -122.4346|Graham 47.0529 -122.2943|Orting 47.0979 -122.2043|DuPont 47.0971 -122.6315|Olympia 47.0379 -122.9007|Lacey 47.0343 -122.8232|Tumwater 47.0073 -122.9093|Yelm 46.9421 -122.6059|Shelton 47.2151 -123.1007|Centralia 46.7162 -122.9543|Chehalis 46.662 -122.964|Bremerton 47.5673 -122.6326|Silverdale 47.6446 -122.6949|Poulsbo 47.736 -122.6465|Port Orchard 47.5404 -122.6363|Bainbridge Island 47.6262 -122.5212|Kingston 47.7987 -122.4982|Vashon 47.4473 -122.4598|Port Townsend 48.117 -122.7604|Sequim 48.0795 -123.1018|Port Angeles 48.1181 -123.4307|Aberdeen 46.9754 -123.8157|Cle Elum 47.1954 -120.9392|Ellensburg 46.9965 -120.5478|Wenatchee 47.4235 -120.3103|Leavenworth 47.5962 -120.6615|Yakima 46.6021 -120.5059|Moses Lake 47.1301 -119.2781|Richland 46.2857 -119.2845|Kennewick 46.2112 -119.1372|Pasco 46.2396 -119.1006|Walla Walla 46.0646 -118.343|Spokane 47.6588 -117.426|Spokane Valley 47.6732 -117.2394|Longview 46.1382 -122.9382|Kelso 46.1468 -122.9084|Ridgefield 45.8151 -122.7426|Battle Ground 45.7807 -122.5334|Vancouver 45.6387 -122.6615|Camas 45.5871 -122.3995|Portland 45.5152 -122.6784|Gresham 45.4982 -122.4318|Beaverton 45.4871 -122.8037|Hillsboro 45.5229 -122.9898|Lake Oswego 45.4207 -122.6706|Hood River 45.7054 -121.5215|Salem 44.9429 -123.0351|Bend 44.0582 -121.3153|Eugene 44.0521 -123.0868|Magnolia 47.6505 -122.4016|Laurelhurst 47.6597 -122.2774|Madison Park 47.6338 -122.2786|Montlake 47.643 -122.304|Madrona 47.6121 -122.2886|Leschi 47.6005 -122.286|Denny-Blaine 47.624 -122.283|Broadmoor 47.635 -122.29|Mount Baker 47.5793 -122.2896|Seward Park 47.551 -122.265|Columbia City 47.559 -122.286|Beacon Hill 47.568 -122.308|Windermere 47.6745 -122.27|View Ridge 47.682 -122.277|Sand Point 47.683 -122.261|Bryant 47.673 -122.285|Wedgwood 47.688 -122.29|Ravenna 47.675 -122.302|Maple Leaf 47.696 -122.318|Wallingford 47.661 -122.334|Green Lake 47.68 -122.328|Phinney Ridge 47.674 -122.354|Crown Hill 47.695 -122.372|Blue Ridge 47.705 -122.373|Broadview 47.722 -122.36|Eastlake 47.642 -122.326|South Lake Union 47.626 -122.338|Belltown 47.615 -122.346|Downtown Seattle 47.605 -122.334|Interbay 47.645 -122.38|Alki 47.579 -122.409|Admiral 47.58 -122.387|Fauntleroy 47.523 -122.386|Arbor Heights 47.51 -122.38|White Center 47.51 -122.348|Skyway 47.49 -122.24|The Highlands 47.737 -122.37|Richmond Beach 47.765 -122.385|Woodway 47.796 -122.383|Clyde Hill 47.6318 -122.2177|Hunts Point 47.6432 -122.229|Yarrow Point 47.6462 -122.2173|Beaux Arts 47.5851 -122.201|West Bellevue 47.615 -122.21|Somerset 47.564 -122.16|Newport Hills 47.549 -122.183|Lakemont 47.561 -122.115|Crossroads 47.618 -122.126|Bridle Trails 47.655 -122.175|Houghton 47.662 -122.203|Rose Hill 47.68 -122.18|Juanita 47.705 -122.212|Finn Hill 47.727 -122.24|Kingsgate 47.729 -122.183|Education Hill 47.69 -122.11|Redmond Ridge 47.695 -122.04|Union Hill 47.68 -122.03|Cottage Lake 47.745 -122.09|Pine Lake 47.59 -122.04|Klahanie 47.577 -122.005|Issaquah Highlands 47.542 -122.013|Snoqualmie Ridge 47.531 -121.864|Kennydale 47.511 -122.2|Renton Highlands 47.497 -122.17|Fairwood 47.448 -122.143|Canyon Park 47.79 -122.21|Maltby 47.805 -122.113|Clearview 47.827 -122.146|Martha Lake 47.851 -122.239|Silver Firs 47.863 -122.15|Harbour Pointe 47.885 -122.295|Three Tree Point 47.45 -122.379|Dash Point 47.32 -122.41|Lake Tapps 47.23 -122.17|Fircrest 47.232 -122.517|Ruston 47.298 -122.513|Fox Island 47.251 -122.629|Suquamish 47.731 -122.552|Port Ludlow 47.925 -122.683|Clinton 47.975 -122.354|Langley 48.0401 -122.406|Freeland 48.009 -122.526|Coupeville 48.2198 -122.6863|La Conner 48.3923 -122.496|Sedro-Woolley 48.5039 -122.2361|Friday Harbor 48.5343 -123.0171|Eatonville 46.8673 -122.2665|Tenino 46.8565 -122.8529|Ocean Shores 46.9737 -124.1563|Westport 46.8901 -124.104|Long Beach 46.3523 -124.0543|Chelan 47.841 -120.016|Ephrata 47.3176 -119.5537|Ritzville 47.1273 -118.3797|Pullman 46.7313 -117.1796|Coeur d'Alene 47.6777 -116.7805|Boise 43.615 -116.2023`;

export const cities: Record<string, { name: string; lat: number; lon: number }> = Object.fromEntries(
  raw.split('|').map(row => { const p = row.split(' '); const lon = Number(p.pop()), lat = Number(p.pop()); const name = p.join(' '); return [key(name), { name, lat, lon }]; }),
);
export const cityNames = Object.values(cities).map(c => c.name).sort();

function key(s: string) { return s.toLowerCase().replace(/[.'’]/g, '').replace(/\s+/g, ' ').trim(); }

/** Finds a city from free text like "issaquah", "Issaquah, WA" or "123 Main St, Kent, WA 98032". */
export function findCity(input: string) {
  const parts = input.split(',').map(p => key(p.replace(/\b(wa|or|id|washington|oregon|idaho)\b/gi, '').replace(/\d{5}(-\d{4})?/, ''))).filter(Boolean);
  for (const p of [...parts].reverse()) if (cities[p]) return cities[p];
  const whole = key(input);
  const hit = Object.keys(cities).filter(k => k.startsWith(whole)).sort((a, b) => a.length - b.length);
  // "issaq" matches Issaquah and Issaquah Highlands: take the shorter name when it starts all the others.
  return whole.length >= 3 && hit.length && hit.every(k => k.startsWith(hit[0])) ? cities[hit[0]] : null;
}

export function straightMiles(a: { lat: number; lon: number }, b: { lat: number; lon: number }) {
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

const oregon = /^(Portland|Gresham|Beaverton|Hillsboro|Lake Oswego|Hood River|Salem|Bend|Eugene)$/, idaho = /^(Coeur d'Alene|Boise)$/;
/** "Issaquah, WA" style label for a known city. */
export function place(c: { name: string }) { return `${c.name}, ${oregon.test(c.name) ? 'OR' : idaho.test(c.name) ? 'ID' : 'WA'}`; }

/** Closest known city to a GPS point, if one is within range. */
export function nearestCity(p: { lat: number; lon: number }, maxMiles = 8) {
  let best: { name: string; lat: number; lon: number } | null = null, dist = maxMiles;
  for (const c of Object.values(cities)) { const m = straightMiles(p, c); if (m < dist) { best = c; dist = m; } }
  return best;
}

/** A job. `single` marks a single-location job (labor only, moving things around in one place): just `load` is used, as the place. */
export type Job = { load: string; unload: string; single?: boolean };
export type SimpleDay = { date: string; office: Office; jobs: Job[]; clockIn: string; clockOut: string; lunch: number; miles?: number | null };
export type Plan = { entries: Entry[]; miles: number; driveMin: number; unknown: string[]; route: string[] };

const SIMPLE_TAG = 'Simple day entry';
const LD_TAG = 'LD day entry';
const SINGLE_WORK = 'Labor, single location';
const SINGLE_DRIVE = 'To job site';
const jobTag = (n: number, total: number) => (total > 1 ? ` (job ${n})` : '');

type Pt = { lat: number; lon: number };
/** Where the day starts or ends: its log label, map point (null if the city is unknown) and notes. */
type End = { name: string; text: string; point: Pt | null; pre: string; post: string; back: string; route: string };
type Stop = { text: string; city: Pt & { name: string } | null; work: string; drive: string };
type Day = { date: string; clockIn: string; clockOut: string; lunch: number; miles?: number | null };

/**
 * Lays out a day from start to end through the stops: pre-trip, then drive to and work at each stop,
 * drive to the end, post-trip. Lunch goes in whichever stop is nearest the middle of the shift.
 * With no stops (a long-distance drive) the drive fills the shift and lunch splits it in two.
 */
function layDay(d: Day, start: End, stops: Stop[], end: End, tag: string, zone: string, newId: () => string): Plan {
  const unknown = [...new Set([...(start.point ? [] : [start.text]), ...stops.filter(s => !s.city).map(s => s.text), ...(end.point ? [] : [end.text])])];
  const t0 = epoch(`${d.date}T${d.clockIn}`, zone), t1 = epoch(`${d.date}T${d.clockOut}`, zone);
  if (t1 <= t0) throw new Error('Clock out must be after clock in.');
  const span = Math.round((t1 - t0) / 60000), lunch = Math.max(0, Math.round(d.lunch));
  if (lunch >= span) throw new Error('Lunch is longer than the whole shift.');

  const points = [start.point, ...stops.map(s => s.city), end.point];
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
  if (!stops.length) drive = [room];
  else if (driveTotal > room) drive = drive.map(m => Math.max(4, Math.floor((m * room) / driveTotal)));
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

  const names = [start.name, ...stops.map(s => (s.city ? place(s.city) : s.text)), end.name];
  const entries: Entry[] = [];
  let t = t0;
  const add = (status: Entry['status'], min: number, from: string, to = '', miles: number | null = null, note = '') => {
    if (min <= 0) return;
    const end = t + min * 60000;
    entries.push({ id: newId(), status, start: t, end, from, to, miles, note, partial: false, source: 'manual' });
    t = end;
  };
  add('On duty', pre, names[0], '', null, start.pre);
  stops.forEach((s, i) => {
    add('Driving', drive[i], names[i], names[i + 1], legs[i], s.drive);
    if (lunch && lunchAt.stop === i) {
      add('On duty', lunchAt.after, names[i + 1], '', null, s.work);
      add('Off duty', lunch, names[i + 1], '', null, 'Lunch break');
      add('On duty', atStop[i] - lunchAt.after, names[i + 1], '', null, s.work);
    } else add('On duty', atStop[i], names[i + 1], '', null, s.work);
  });
  const last = names[stops.length];
  if (!stops.length && lunch) {
    // Straight through: stop for lunch on the road halfway through the working time.
    const first = Math.min(drive[0], Math.max(1, target - pre)), firstMiles = Math.round((legs[0] * first) / drive[0] * 10) / 10;
    add('Driving', first, last, 'En route', firstMiles, end.back);
    add('Off duty', lunch, 'En route', '', null, 'Lunch break');
    add('Driving', drive[0] - first, 'En route', end.name, Math.round((legs[0] - firstMiles) * 10) / 10, end.back);
  } else add('Driving', drive[stops.length], last, end.name, legs[stops.length], end.back);
  add('On duty', Math.round((t1 - t) / 60000), end.name, '', null, end.post);
  entries[0].note += ` | ${tag}: drive times and miles estimated from cities.`;
  const route = [start.route, ...stops.map(s => (s.city ? s.city.name : s.text)), end.route];
  return { entries, miles: Math.round(legs.reduce((a, b) => a + b, 0) * 10) / 10, driveMin: drive.reduce((a, b) => a + b, 0), unknown, route };
}

const officeEnd = (o: Office, back = 'Return to office', route = 'back'): End => ({ name: offices[o].label, text: o, point: offices[o], pre: 'Pre-trip inspection / prep at office', post: 'Post-trip / unload equipment at office', back, route });

/**
 * Lays out a day: pre-trip, then for each job drive to load, load, drive to unload, unload (or, for a single-location
 * job, drive there and work); drive back, post-trip. Lunch goes in whichever stop is nearest the middle of the shift.
 */
export function planSimpleDay(d: SimpleDay, zone: string, newId: () => string = () => crypto.randomUUID()): Plan {
  const jobs = d.jobs.map(j => ({ load: j.load.trim(), unload: j.single ? '' : j.unload.trim(), single: !!j.single })).filter(j => j.load || j.unload);
  if (!jobs.length || jobs.some(j => !j.load || (!j.single && !j.unload))) {
    throw new Error(d.jobs.length > 1 ? 'Enter the cities for each job.' : jobs[0]?.single || d.jobs[0]?.single ? 'Enter the city of the job.' : 'Enter both a load city and an unload city.');
  }
  const stops = jobs.flatMap((j, n) => j.single ? [
    { text: j.load, city: findCity(j.load), work: `${SINGLE_WORK}${jobTag(n + 1, jobs.length)}`, drive: `${SINGLE_DRIVE}${jobTag(n + 1, jobs.length)}` },
  ] : [
    { text: j.load, city: findCity(j.load), work: `Loading${jobTag(n + 1, jobs.length)}`, drive: `To load${jobTag(n + 1, jobs.length)}` },
    { text: j.unload, city: findCity(j.unload), work: `Unloading${jobTag(n + 1, jobs.length)}`, drive: `To unload${jobTag(n + 1, jobs.length)}` },
  ]);
  return layDay(d, { ...officeEnd(d.office), route: d.office }, stops, officeEnd(d.office), SIMPLE_TAG, zone, newId);
}

// ---- LD (long-distance) day: starts and/or ends at a hotel, with an optional unload on the way ----

export type LdPlace = { at: 'office' | 'hotel'; office: Office; hotel: string };
/** `unload` is null when there is no unload today. */
export type LdDay = { date: string; start: LdPlace; unload: string | null; end: LdPlace; clockIn: string; clockOut: string; lunch: number; miles?: number | null };

const HOTEL = 'Hotel – ';
function hotelEnd(text: string): End {
  const city = findCity(text);
  return { name: HOTEL + (city ? place(city) : text), text, point: city, pre: 'Pre-trip inspection at hotel', post: 'Post-trip inspection at hotel', back: 'To hotel', route: `Hotel (${city ? city.name : text})` };
}

/**
 * Lays out a long-distance day: pre-trip at the office or hotel, an optional drive to the unload and
 * unloading, then the drive to the hotel or back to the office and a post-trip there.
 * Covers office → hotel, office → unload → hotel, hotel → hotel, hotel → unload → hotel/office, hotel → office.
 */
export function planLdDay(d: LdDay, zone: string, newId: () => string = () => crypto.randomUUID()): Plan {
  const startHotel = d.start.hotel.trim(), endHotel = d.end.hotel.trim(), unload = d.unload?.trim() ?? null;
  if (d.start.at === 'hotel' && !startHotel) throw new Error('Enter the city of the hotel you started from.');
  if (d.end.at === 'hotel' && !endHotel) throw new Error('Enter the city of the hotel you ended at.');
  if (unload === '') throw new Error('Enter the unload city, or choose No unload.');
  if (d.start.at === 'office' && d.end.at === 'office') throw new Error('Office to office is a Simple day. Pick a hotel for the start or end, or use Simple day.');
  const start = d.start.at === 'office' ? { ...officeEnd(d.start.office), route: d.start.office } : hotelEnd(startHotel);
  const end = d.end.at === 'office' ? officeEnd(d.end.office, 'Return to office', `${d.end.office} office`) : hotelEnd(endHotel);
  const stops: Stop[] = unload ? [{ text: unload, city: findCity(unload), work: 'Unloading', drive: 'To unload' }] : [];
  return layDay(d, start, stops, end, LD_TAG, zone, newId);
}

/** Rebuilds the LD day answers from entries it created earlier, so the day can be edited. */
export function readLdDay(entries: Entry[], zone: string): LdDay | null {
  const es = [...entries].sort((a, b) => a.start - b.start);
  if (!es.length || !es[0].note.includes(LD_TAG) || es.some(e => e.end === null)) return null;
  const city = (s: string) => s.replace(/, (WA|OR|ID)$/, '');
  const where = (label: string): LdPlace | null => {
    const office = (Object.keys(offices) as Office[]).find(o => offices[o].label === label);
    if (office) return { at: 'office', office, hotel: '' };
    return label.startsWith(HOTEL) ? { at: 'hotel', office: 'Preston', hotel: city(label.slice(HOTEL.length)) } : null;
  };
  const start = where(es[0].from), end = where(es[es.length - 1].from);
  if (!start || !end) return null;
  if (start.at === 'hotel' && end.at === 'office') start.office = end.office;
  if (end.at === 'hotel' && start.at === 'office') end.office = start.office;
  const drop = es.find(e => e.status === 'Driving' && e.note === 'To unload');
  const lunch = es.filter(e => e.status === 'Off duty' && e.note === 'Lunch break').reduce((n, e) => n + (e.end! - e.start) / 60000, 0);
  const day: LdDay = { date: dayKey(es[0].start, zone), start, unload: drop ? city(drop.to) : null, end, clockIn: localInput(es[0].start, zone).slice(11), clockOut: localInput(es[es.length - 1].end!, zone).slice(11), lunch: Math.round(lunch), miles: null };
  const saved = Math.round(es.reduce((n, e) => n + (e.status === 'Driving' ? e.miles ?? 0 : 0), 0) * 10) / 10;
  try { if (Math.abs(planLdDay(day, zone, () => '').miles - saved) > 0.15) day.miles = saved; } catch { day.miles = saved; }
  return day;
}

/** Rebuilds the Simple day answers from entries it created earlier, so the day can be edited. */
export function readSimpleDay(entries: Entry[], zone: string): SimpleDay | null {
  const es = [...entries].sort((a, b) => a.start - b.start);
  if (!es.length || !es[0].note.includes(SIMPLE_TAG) || es.some(e => e.end === null)) return null;
  const office = (Object.keys(offices) as Office[]).find(o => offices[o].label === es[0].from);
  if (!office) return null;
  const city = (s: string) => s.replace(/, (WA|OR|ID)$/, '');
  const jobs: Job[] = [];
  for (const e of es) {
    if (e.status !== 'Driving') continue;
    if (e.note.startsWith('To load')) jobs.push({ load: city(e.to), unload: '' });
    else if (e.note.startsWith(SINGLE_DRIVE)) jobs.push({ load: city(e.to), unload: '', single: true });
    else if (e.note.startsWith('To unload') && jobs.length) jobs[jobs.length - 1].unload = city(e.to);
  }
  if (!jobs.length || jobs.some(j => !j.single && !j.unload)) return null;
  const lunch = es.filter(e => e.status === 'Off duty' && e.note === 'Lunch break').reduce((n, e) => n + (e.end! - e.start) / 60000, 0);
  const day: SimpleDay = { date: dayKey(es[0].start, zone), office, jobs, clockIn: localInput(es[0].start, zone).slice(11), clockOut: localInput(es[es.length - 1].end!, zone).slice(11), lunch: Math.round(lunch), miles: null };
  // If the saved miles differ from the city estimate, the driver typed odometer miles; keep them.
  const saved = Math.round(es.reduce((n, e) => n + (e.status === 'Driving' ? e.miles ?? 0 : 0), 0) * 10) / 10;
  try { if (Math.abs(planSimpleDay(day, zone, () => '').miles - saved) > 0.15) day.miles = saved; } catch { day.miles = saved; }
  return day;
}
