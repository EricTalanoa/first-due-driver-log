import { useEffect, useState } from 'react';
import { statuses, type Entry } from '../lib/log';
import { chartSegments, activityOf, activities } from '../lib/hos';

// The DOT record-of-duty-status grid: 24 hours across, the four duty lines down, one continuous line,
// 15-minute ticks, a total for each line, and remarks with the place of every change.

const hours = ['Mid', ...Array.from({ length: 11 }, (_, i) => String(i + 1)), 'Noon', ...Array.from({ length: 11 }, (_, i) => String(i + 1)), 'Mid'];
// Full layout for wide screens and print; on a phone, the short ELD-style labels so the whole day fits.
const full = { L: 180, HOUR: 40, R: 80, ROW: 38, TOP: 28, every: 1, ticks: [7, 13], labels: ['1. Off duty', '2. Sleeper berth', '3. Driving', '4. On duty (not driving)'] };
const compact = { L: 34, HOUR: 15, R: 44, ROW: 30, TOP: 22, every: 3, ticks: [0, 6], labels: ['OFF', 'SB', 'D', 'ON'] };
function useNarrow() {
  const [narrow, setNarrow] = useState(false);
  useEffect(() => { const q = matchMedia('(max-width: 600px)'); const on = () => setNarrow(q.matches); on(); q.addEventListener('change', on); return () => q.removeEventListener('change', on); }, []);
  return narrow;
}
const hm = (ms: number) => { const m = Math.round(ms / 60000); return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`; };

export function HosChart({ entries, day, zone, now, onPick }: { entries: Entry[]; day: string; zone: string; now: number; onPick?: (e: Entry) => void }) {
  const narrow = useNarrow();
  const { L, HOUR, R, ROW, TOP, every, ticks, labels } = narrow ? compact : full;
  const W = L + 24 * HOUR + R, HGT = TOP + ROW * 4 + 30;
  const { segments, start, end, upto } = chartSegments(entries, day, zone, now);
  const span = end - start;
  const x = (t: number) => L + ((t - start) / span) * 24 * HOUR;
  const y = (s: (typeof statuses)[number]) => TOP + ROW * statuses.indexOf(s) + ROW / 2;
  const totals = statuses.map(s => segments.filter(g => g.status === s).reduce((n, g) => n + g.end - g.start, 0));
  let path = '';
  segments.forEach((g, i) => { path += `${i ? 'L' : 'M'}${x(g.start).toFixed(1)},${y(g.status)}L${x(g.end).toFixed(1)},${y(g.status)}`; });
  const clock = (t: number) => new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', minute: '2-digit' }).format(t);
  // Remarks: every recorded change of duty status with its place, as the rules ask for.
  const remarks = segments.filter(g => g.entry && g.entry.start >= start).map(g => ({ t: g.start, e: g.entry!, what: activities[activityOf(g.entry!)].label }));
  const last = [...segments].reverse().find(g => g.entry);
  const clockOut = last?.entry?.end != null && last.entry.end <= upto && last.entry.end < end ? last.entry : null;
  const partial = upto < end;
  return <div className="hos">
    <div className={narrow ? 'hos-scroll narrow' : 'hos-scroll'}>
      <svg viewBox={`0 0 ${W} ${HGT}`} role="img" aria-label={`Duty status chart for ${day}. ${statuses.map((s, i) => `${s} ${hm(totals[i])}`).join(', ')}.`}>
        <rect x={L} y={TOP} width={24 * HOUR} height={ROW * 4} className="hos-bg" />
        {hours.map((h, i) => i % every ? null : <text key={i} x={L + i * HOUR} y={TOP - 9} className="hos-hour">{h}</text>)}
        {statuses.map((s, r) => <g key={s}>
          <text x={narrow ? 4 : 8} y={TOP + ROW * r + ROW / 2 + 5} className="hos-label">{labels[r]}</text>
          <line x1={L} x2={L + 24 * HOUR} y1={TOP + ROW * (r + 1)} y2={TOP + ROW * (r + 1)} className="hos-grid" />
          {Array.from({ length: 24 * 4 }, (_, q) => q % 4 && (q % 2 || ticks[0]) ? <line key={q} x1={L + q * HOUR / 4} x2={L + q * HOUR / 4} y1={TOP + ROW * (r + 1)} y2={TOP + ROW * (r + 1) - (q % 2 ? ticks[0] : ticks[1])} className="hos-tick" /> : null)}
          <text x={W - 10} y={TOP + ROW * r + ROW / 2 + 6} className="hos-total">{hm(totals[r])}</text>
        </g>)}
        <line x1={L} x2={L + 24 * HOUR} y1={TOP} y2={TOP} className="hos-grid" />
        {Array.from({ length: 25 }, (_, i) => <line key={i} x1={L + i * HOUR} x2={L + i * HOUR} y1={TOP} y2={TOP + ROW * 4} className="hos-grid" />)}
        {path && <path d={path} className="hos-line" />}
        {onPick && segments.filter(g => g.entry).map(g => <rect key={g.entry!.id + g.start} x={x(g.start)} y={TOP + ROW * statuses.indexOf(g.status)} width={Math.max(6, x(g.end) - x(g.start))} height={ROW} className="hos-hit" onClick={() => onPick(g.entry!)}><title>{`${g.status}: ${clock(g.start)} – ${clock(g.end)}`}</title></rect>)}
        {partial && upto > start && <line x1={x(upto)} x2={x(upto)} y1={TOP - 4} y2={TOP + ROW * 4 + 4} className="hos-now" />}
        <text x={W - 10} y={TOP + ROW * 4 + 22} className="hos-total sum">{hm(totals.reduce((a, b) => a + b, 0))}</text>
        <text x={L} y={TOP + ROW * 4 + 22} className="hos-foot">{partial ? 'So far today' : span !== 86400000 ? 'Daylight-saving day' : narrow ? 'Blank time = off duty' : 'Blank time is shown as off duty'}</text>
      </svg>
    </div>
    <div className="hos-remarks">
      <strong>Remarks</strong>
      {!remarks.length ? <p className="subtle">No duty changes recorded. Each change will be listed here with its place.</p> :
        <ol>{remarks.map(r => <li key={r.e.id}><span>{clock(r.t)}</span><span>{r.what}{r.e.status === 'Driving' && r.e.to ? ` to ${r.e.to}` : ''}</span><span className="subtle">{r.e.from || 'Place not entered'}</span></li>)}
          {clockOut && <li><span>{clock(clockOut.end!)}</span><span>Clock out</span><span className="subtle">{clockOut.to || clockOut.from || 'Place not entered'}</span></li>}</ol>}
    </div>
  </div>;
}
