import { useState, type FormEvent } from 'react';
import { Plus, Printer, ShieldCheck, Pencil, Trash2, Calculator, ClipboardList } from 'lucide-react';
import { Modal, Field } from './ui';
import { HosChart } from './hos-chart';
import { cityNames } from '../lib/simple-day';
import { bounds, dayKey, epoch, type Entry, type Log } from '../lib/log';
import { activities, activityOf, nextSteps, estimateMiles, hosClocks, toEntries, toSteps, stepTime, hhmm, hotel, PRESTON, LD_MARK, type Activity, type Step } from '../lib/hos';

type Act = Activity | 'clockout';
const H = 3600000;
const shortPlace = (p: string) => (p === PRESTON ? 'Preston office' : p);
const hm = (ms: number) => { const m = Math.max(0, Math.round(Math.abs(ms) / 60000)); return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`; };
const shiftDay = (d: string, n: number) => new Date(Date.parse(d + 'T12:00Z') + n * 86400000).toISOString().slice(0, 10);
const dayLabel = (d: string, opts: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', ...opts }).format(Date.parse(d + 'T12:00Z'));

/** The button label for a step, which reads differently depending on what the driver is doing now. */
function stepLabel(act: Act, now: Activity | null) {
  if (act === 'clockout') return 'Clock out';
  if (act === 'pretrip') return 'Clock in';
  if (act === 'drive') return now === 'riding' ? 'Take the wheel' : 'Start driving';
  if (act === 'posttrip') return now === 'drive' || now === 'riding' ? 'Arrive · post-trip' : 'Post-trip inspection';
  if (act === 'work') return now === 'drive' ? 'Stop · other work' : 'Back to work';
  return activities[act].label;
}

/** Where the driver ended yesterday, for suggesting this morning's hotel. Older days are ignored. */
function lastPlace(entries: Entry[], before: number) {
  const prev = entries.filter(e => e.end !== null && e.end <= before && e.end > before - 24 * H).sort((a, b) => b.end! - a.end!)[0];
  return prev ? (prev.to || prev.from).trim() : '';
}

function PlaceInput({ value, onChange, suggestions, label }: { value: string; onChange: (p: string) => void; suggestions: string[]; label: string }) {
  const chips = [...new Set(suggestions.filter(Boolean))].slice(0, 5);
  const custom = !chips.includes(value);
  const [isHotel, setIsHotel] = useState(value.startsWith('Hotel – '));
  const text = custom ? value.replace(/^Hotel – /, '') : '';
  const write = (t: string, h = isHotel) => onChange(t.trim() ? (h ? hotel(t) : t) : '');
  return <div className="field place-input"><span>{label}</span>
    {chips.length > 0 && <div className="place-chips" role="group" aria-label={label}>{chips.map(c => <button type="button" key={c} aria-pressed={value === c} onClick={() => onChange(c)}>{shortPlace(c)}</button>)}</div>}
    <div className="place-custom"><input list="city-list" autoComplete="off" placeholder={isHotel ? 'Hotel city or address' : chips.length ? 'Or type a city or address' : 'City or address'} value={text} onChange={e => write(e.target.value)} />
      <label className="hotel-check"><input type="checkbox" checked={isHotel} onChange={e => { setIsHotel(e.target.checked); if (text) write(text, e.target.checked); }} /> Hotel</label></div>
  </div>;
}

function StepDialog({ act, current, active, zone, suggestions, busy, now: shown, onClose, onSave }: { now: number; act: Act; current: Activity | null; active: Entry | null; zone: string; suggestions: string[]; busy: boolean; onClose: () => void; onSave: (at: number, place: string, miles: number | null) => Promise<void> }) {
  const ending = active?.status === 'Driving';
  const [time, setTime] = useState(hhmm(shown, zone));
  const [place, setPlace] = useState(ending || !active ? (active ? '' : suggestions[0] ?? '') : active.from);
  const [miles, setMiles] = useState(''), [error, setError] = useState('');
  const estimate = ending ? estimateMiles(active!.from, place) : null;
  async function submit(e: FormEvent) {
    e.preventDefault(); setError('');
    const now = Date.now();
    try {
      let at = epoch(`${dayKey(now, zone)}T${time}`, zone);
      if (at > now + 60000) at = epoch(`${dayKey(now - 86400000, zone)}T${time}`, zone);
      if (active && at <= active.start) throw new Error(`That's before your current ${activities[activityOf(active)].label.toLowerCase()} started. Check the time.`);
      if (!place.trim()) throw new Error('Enter where you are. The log needs the city at every change.');
      await onSave(at, place.trim(), miles === '' ? null : Number(miles));
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save.'); }
  }
  return <Modal title={stepLabel(act, current)} onClose={onClose}><form onSubmit={submit} className="simple-day">
    <Field label="Time"><input type="time" required value={time} onChange={e => setTime(e.target.value)} /></Field>
    <PlaceInput label={act === 'clockout' ? 'Where you finished' : act === 'pretrip' ? 'Starting from' : ending ? 'Where you stopped' : 'Where you are'} value={place} onChange={setPlace} suggestions={suggestions} />
    {ending && <Field label={`Miles for this drive${estimate !== null ? ` · estimate ${estimate.toFixed(1)}` : ''}`}><input type="number" inputMode="decimal" min="0" max="100000" step="0.1" placeholder={estimate !== null ? 'Leave blank to use the estimate' : 'City not recognized: enter miles'} value={miles} onChange={e => setMiles(e.target.value)} /></Field>}
    {act === 'riding' && <p className="subtle">Riding in the passenger seat while your co-driver drives is logged as On duty.</p>}
    {act === 'fuel' && <p className="subtle">Fueling is On duty under DOT rules. Use Quick break for a stop where you are off work.</p>}
    {error && <p className="alert" role="alert">{error}</p>}
    <div className="modal-actions"><button className="secondary" type="button" onClick={onClose}>Cancel</button><button className="primary" disabled={busy}>{busy ? 'Saving…' : 'Save'}</button></div>
  </form></Modal>;
}

function Clocks({ entries, now, onClock }: { entries: Entry[]; now: number; onClock: boolean }) {
  const c = hosClocks(entries, now);
  const tile = (label: string, left: number, of: string, idle?: string) => <div className={left < 0 ? 'over' : left < H ? 'warn' : ''}><span>{label}</span><strong>{idle ?? (left < 0 ? `Over ${hm(left)}` : hm(left))}</strong><small>{of}</small></div>;
  return <div className="hos-clocks" aria-label="Hours of service">
    {tile('Driving left', c.drive, 'of 11 hours', c.shiftStart === null ? '11h 00m' : undefined)}
    {tile('Work window left', c.window, 'of 14 hours', c.shiftStart === null ? '14h 00m' : undefined)}
    {tile('Break due in', c.breakDue, '30 min after 8 h driving', !onClock && c.shiftStart === null ? '8h 00m' : undefined)}
    {tile('Week left', c.cycle, 'of 70 hours in 8 days')}
  </div>;
}

export function LdPage({ log, now, busy, loaded, onStep, onEdit, onFill, onEstimate }: { log: Log; now: number; busy: boolean; loaded: boolean; onStep: (act: Act, at: number, place: string, miles: number | null) => Promise<void>; onEdit: (e: Entry) => void; onFill: (day: string) => void; onEstimate: () => void }) {
  const zone = log.profile.zone, active = log.active;
  const today = dayKey(now, zone), [t0] = bounds(today, zone);
  const all = [...log.entries, ...(active ? [active] : [])];
  const current = active ? activityOf(active) : null;
  const [step, setStep] = useState<Act | null>(null), [inspect, setInspect] = useState(false);
  const clock = (t: number) => new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', minute: '2-digit' }).format(t);
  const prev = lastPlace(log.entries, active?.start ?? t0);
  const todays = all.filter(e => e.start >= t0).flatMap(e => [e.from, e.to]).filter(Boolean).reverse();
  const suggestions = !active ? [prev && prev !== PRESTON ? (prev.startsWith('Hotel – ') ? prev : hotel(prev)) : '', PRESTON].filter(Boolean)
    : step === 'clockout' || step === 'posttrip' ? [...todays.filter(p => p.startsWith('Hotel – ')), PRESTON, ...todays] : [...todays, PRESTON];
  const steps = nextSteps(current);
  return <section className="paper ld-live">
    <div className="ld-head"><div><span className="eyebrow">LD · {dayLabel(today, { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase()}</span><h2>{active ? activities[current!].note : 'Off the clock'}</h2>
      <p className="subtle">{active ? `Since ${clock(active.start)}${active.from ? ` · ${shortPlace(active.from)}` : ''}` : 'Nothing logged yet today. Tap Clock in when you start your day.'}</p></div>
      <span className={`status-pill s${active ? ['Off duty', 'Sleeper berth', 'Driving', 'On duty'].indexOf(active.status) : 0}`}>{active?.status ?? 'Off duty'}</span></div>
    <div className="step-buttons">{steps.map((s, i) => <button key={s} className={i === 0 && current !== 'drive' && current !== 'riding' ? 'primary' : 'secondary'} disabled={!loaded || busy} onClick={() => setStep(s)}>{stepLabel(s, current)}</button>)}</div>
    {(active || all.some(e => e.start >= t0)) && <Clocks entries={all} now={now} onClock={!!active && active.status !== 'Off duty'} />}
    <HosChart entries={all} day={today} zone={zone} now={now} onPick={e => e.id !== active?.id && onEdit(e)} />
    <div className="ld-actions">
      <button className="secondary" disabled={!loaded} onClick={() => setInspect(true)}><ShieldCheck size={18} /> Inspection view</button>
      <button className="text-button" disabled={!loaded} onClick={() => onFill(today)}><ClipboardList size={16} /> Fill in or fix a day</button>
      <button className="text-button" disabled={!loaded} onClick={onEstimate}><Calculator size={16} /> Estimate an LD day</button>
    </div>
    <datalist id="city-list">{cityNames.map(c => <option key={c} value={c} />)}</datalist>
    {step && <StepDialog act={step} current={current} active={active} zone={zone} suggestions={suggestions} busy={busy} now={now} onClose={() => !busy && setStep(null)} onSave={async (at, place, miles) => { await onStep(step, at, place, miles); setStep(null); }} />}
    {inspect && <InspectionView log={log} now={now} onClose={() => setInspect(false)} />}
  </section>;
}

/** Today and the previous 7 days, the way an officer asks to see them, with the header details. */
export function InspectionView({ log, now, onClose }: { log: Log; now: number; onClose: () => void }) {
  const zone = log.profile.zone, p = log.profile;
  const all = [...log.entries, ...(log.active ? [log.active] : [])];
  const today = dayKey(now, zone);
  const days = Array.from({ length: 8 }, (_, i) => shiftDay(today, -i));
  const c = hosClocks(all, now);
  return <Modal title="Record of duty status" onClose={onClose} wide><div className="inspection">
    <dl className="inspect-head">
      <div><dt>Driver</dt><dd>{p.name || 'Not set'}</dd></div><div><dt>Co-driver</dt><dd>{p.coDriver || 'None'}</dd></div>
      <div><dt>Carrier</dt><dd>{p.carrier}</dd></div><div><dt>Truck / trailer</dt><dd>{p.vehicle || 'Not set'}</dd></div>
      <div><dt>Main office</dt><dd>{p.office || 'Not set'}</dd></div><div><dt>Home terminal</dt><dd>{p.terminal || 'Not set'}</dd></div>
      <div><dt>24-hour period starts</dt><dd>Midnight, {zone.replaceAll('_', ' ')}</dd></div><div><dt>On duty, last 8 days</dt><dd>{hm(70 * H - c.cycle)} of 70h</dd></div>
    </dl>
    <div className="modal-actions no-print"><button className="secondary" onClick={() => window.print()}><Printer size={18} /> Print / PDF</button></div>
    {days.map(d => {
      const [s, e] = bounds(d, zone);
      const miles = all.filter(x => x.status === 'Driving' && x.start >= s && x.start < e).reduce((n, x) => n + (x.miles ?? 0), 0);
      const any = all.some(x => x.start < e && (x.end ?? now) > s);
      return <div key={d} className="inspect-day"><h3>{dayLabel(d, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}<span>{any ? `${miles.toFixed(1)} mi driving` : 'Off duty all day'}</span></h3>
        <HosChart entries={all} day={d} zone={zone} now={now} /></div>;
    })}
    <p className="signature">I certify these entries are true and correct. Driver’s signature: ____________________________</p>
  </div></Modal>;
}

type Row = { id: string; time: string; act: Act; place: string; miles: string };

/** Fill in a day after the fact, or fix one: a list of status changes from clock in to clock out. */
export function TimelineEditor({ day, zone, busy, now, ld, existing, onClose, onSave }: { ld?: boolean; now: number; day: string; zone: string; busy: boolean; existing: (d: string) => Entry[]; onClose: () => void; onSave: (entries: Entry[], date: string, replace: boolean) => Promise<void> }) {
  const [prior] = useState(() => existing(day).filter(e => e.end !== null));
  const [date, setDate] = useState(day), [error, setError] = useState('');
  const [rows, setRows] = useState<Row[]>(() => prior.length
    ? toSteps(prior).map(s => ({ id: s.id, time: hhmm(s.time, zone), act: s.act, place: s.place, miles: s.miles?.toString() ?? '' }))
    : [{ id: crypto.randomUUID(), time: '07:00', act: 'pretrip', place: PRESTON, miles: '' }]);
  const editing = prior.length > 0;
  const others = existing(date);
  const set = (i: number, k: keyof Row, v: string) => { setError(''); setRows(r => r.map((x, n) => (n === i ? { ...x, [k]: v } : x))); };
  const places = [...new Set([PRESTON, ...rows.map(r => r.place).filter(Boolean)])];
  const steps: Step[] = [];
  let entries: Entry[] = [], problem = '';
  try {
    for (const r of rows) {
      if (!/^\d\d:\d\d$/.test(r.time)) throw new Error('Enter a time for every step.');
      steps.push({ id: r.id, time: stepTime(date, r.time, zone, steps[steps.length - 1]?.time), act: r.act, place: r.place, miles: r.miles === '' ? null : Number(r.miles) });
    }
    entries = toEntries(steps, ld || prior[0]?.note.includes(LD_MARK) ? LD_MARK : '');
  } catch (e) { problem = e instanceof Error ? e.message : 'Check the steps.'; }
  const last = rows[rows.length - 1]?.act;
  const lastAct = last && last !== 'clockout' ? last : null;
  function add(act: Act) {
    const l = rows[rows.length - 1];
    const [h, m] = l.time.split(':').map(Number), t = (h * 60 + m + 30) % 1440;
    setRows([...rows, { id: crypto.randomUUID(), time: `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`, act, place: l.act === 'drive' || l.act === 'riding' ? '' : l.place, miles: '' }]);
  }
  async function submit(e: FormEvent) {
    e.preventDefault(); setError('');
    try {
      if (problem) throw new Error(problem);
      const blank = steps.findIndex(s => !s.place.trim());
      if (blank >= 0) throw new Error(`Step ${blank + 1} needs a place. The log needs the city at every change.`);
      const unknown = entries.find(x => x.status === 'Driving' && x.miles === null);
      if (unknown) throw new Error(`Couldn't estimate the drive from “${unknown.from}” to “${unknown.to}”. Enter its miles.`);
      await onSave(entries, date, editing || others.length > 0);
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save this day.'); }
  }
  return <Modal title={editing ? 'Fix this day' : 'Fill in a day'} onClose={onClose} wide><form onSubmit={submit} className="simple-day timeline">
    <Field label="Date"><input type="date" required disabled={editing} value={date} onChange={e => e.target.value && setDate(e.target.value)} /></Field>
    <datalist id="place-list">{[...places, ...cityNames].map(c => <option key={c} value={c} />)}</datalist>
    <ol className="steps">{rows.map((r, i) => {
      const est = r.act === 'drive' && rows[i + 1] ? estimateMiles(r.place, rows[i + 1].place) : null;
      return <li key={r.id}>
        <input aria-label={`Step ${i + 1} time`} type="time" required value={r.time} onChange={e => set(i, 'time', e.target.value)} />
        <select aria-label={`Step ${i + 1} activity`} value={r.act} onChange={e => set(i, 'act', e.target.value)}>
          {i === 0 ? <option value="pretrip">Clock in · pre-trip</option> : <>{(Object.keys(activities) as Activity[]).map(a => <option key={a} value={a}>{activities[a].label === activities[a].status ? activities[a].label : `${activities[a].label} · ${activities[a].status}`}</option>)}<option value="clockout">Clock out</option></>}
        </select>
        <input aria-label={`Step ${i + 1} place`} list="place-list" autoComplete="off" placeholder="City, address or hotel" value={r.place} onChange={e => set(i, 'place', e.target.value)} />
        {r.act === 'drive' ? <input aria-label={`Step ${i + 1} miles`} type="number" inputMode="decimal" min="0" step="0.1" placeholder={est !== null ? `${est.toFixed(1)} mi` : 'Miles'} value={r.miles} onChange={e => set(i, 'miles', e.target.value)} /> : <span />}
        {i > 0 ? <button type="button" className="icon" aria-label={`Remove step ${i + 1}`} onClick={() => setRows(rows.filter((_, n) => n !== i))}><Trash2 size={17} /></button> : <span />}
      </li>;
    })}</ol>
    {lastAct ? <div className="add-steps"><span className="subtle"><Plus size={14} /> Next:</span>{nextSteps(lastAct).map(a => <button type="button" key={a} className="chip" onClick={() => add(a)}>{stepLabel(a, lastAct)}</button>)}</div>
      : <p className="subtle">Day ends at clock out. Remove it to add more steps.</p>}
    <p className="subtle">Drive miles are estimated from the places on either side; type miles to override. A time earlier than the step before it is read as after midnight.</p>
    {entries.length > 0 && !problem && <HosChart entries={entries} day={date} zone={zone} now={now} />}
    {problem && <p className="inline-note">{problem}</p>}
    {!editing && others.length > 0 && <p className="replace-note"><Pencil size={16} /> This replaces the {others.length} {others.length === 1 ? 'entry' : 'entries'} already logged on this date.</p>}
    {error && <p className="alert" role="alert">{error}</p>}
    <div className="modal-actions"><button className="secondary" type="button" onClick={onClose}>Cancel</button><button className="primary" disabled={busy || !!problem}>{busy ? 'Saving…' : 'Save day'}</button></div>
  </form></Modal>;
}
