import { supabase } from './supabase';
import { initialLog, validateLog, type Entry, type Log, type Profile } from './log';

// Maps the app's in-memory log to the Supabase tables and back.

type Row = {
  id: string; status: Entry['status']; start_at: string; end_at: string | null; from_place: string; to_place: string; miles: number | null;
  note: string; partial: boolean; source: Entry['source']; last_point: Entry['lastPoint'] | null; document: string | null; shipper: string | null; commodity: string | null;
};
type ProfileRow = { name: string; carrier: string; terminal: string; office: string; vehicle: string; co_driver: string; zone: string };

const iso = (t: number) => new Date(t).toISOString();
function toRow(e: Entry): Row {
  return { id: e.id, status: e.status, start_at: iso(e.start), end_at: e.end === null ? null : iso(e.end), from_place: e.from, to_place: e.to, miles: e.miles, note: e.note,
    partial: e.partial, source: e.source, last_point: e.lastPoint ?? null, document: e.document ?? null, shipper: e.shipper ?? null, commodity: e.commodity ?? null };
}
function fromRow(r: Row): Entry {
  const e: Entry = { id: r.id, status: r.status, start: Date.parse(r.start_at), end: r.end_at === null ? null : Date.parse(r.end_at), from: r.from_place, to: r.to_place,
    miles: r.miles, note: r.note, partial: r.partial, source: r.source };
  if (r.last_point) e.lastPoint = r.last_point;
  if (r.document !== null) e.document = r.document;
  if (r.shipper !== null) e.shipper = r.shipper;
  if (r.commodity !== null) e.commodity = r.commodity;
  return e;
}

function friendly(error: { code?: string; message: string }) {
  if (error.code === '23P01') return 'Duty periods cannot overlap. Adjust the times first.';
  if (error.code === '42501' || /JWT|not signed in|Sign in/i.test(error.message)) return 'Your sign-in expired. Sign in again; your open form is still here.';
  if (/fetch|network/i.test(error.message)) return 'Could not reach the server. Check your connection and try again. Your open entry is still here.';
  return error.message || 'Your changes were not saved.';
}

export async function loadLog(): Promise<Log> {
  const log = initialLog();
  const { data: profile, error: pe } = await supabase.from('profiles').select('name,carrier,terminal,office,vehicle,co_driver,zone').maybeSingle<ProfileRow>();
  if (pe) throw new Error(friendly(pe));
  if (profile) log.profile = { name: profile.name, carrier: profile.carrier, terminal: profile.terminal, office: profile.office, vehicle: profile.vehicle, coDriver: profile.co_driver, zone: profile.zone };
  // Supabase returns at most 1000 rows per request, so page through.
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase.from('entries').select('id,status,start_at,end_at,from_place,to_place,miles,note,partial,source,last_point,document,shipper,commodity').order('start_at').range(from, from + 999).returns<Row[]>();
    if (error) throw new Error(friendly(error));
    for (const r of data) { const e = fromRow(r); if (e.end === null) log.active = e; else log.entries.push(e); }
    if (data.length < 1000) break;
  }
  return log;
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** Saves only what changed between two versions of the log, in one transaction. */
export async function saveLog(prev: Log, next: Log) {
  validateLog(next);
  const before = new Map([...prev.entries, ...(prev.active ? [prev.active] : [])].map(e => [e.id, e]));
  const after = [...next.entries, ...(next.active ? [next.active] : [])];
  const ids = new Set(after.map(e => e.id));
  const upserts = after.filter(e => !same(before.get(e.id), e)).map(toRow);
  const deletes = [...before.keys()].filter(id => !ids.has(id));
  const profile: Profile | null = same(prev.profile, next.profile) ? null : next.profile;
  if (!upserts.length && !deletes.length && !profile) return;
  const { error } = await supabase.rpc('save_log', { upserts, deletes, profile });
  if (error) throw new Error(friendly(error));
}

