export const statuses = ['Off duty', 'Sleeper berth', 'Driving', 'On duty'] as const;
export type Status = typeof statuses[number];
export type Point = { lat: number; lon: number; time: number };
export type Entry = { id: string; status: Status; start: number; end: number | null; from: string; to: string; miles: number | null; note: string; partial: boolean; source: 'manual' | 'gps'; lastPoint?: Point; document?: string; shipper?: string; commodity?: string };
export type Profile = { name: string; carrier: string; terminal: string; office: string; vehicle: string; coDriver: string; zone: string };
export type Log = { entries: Entry[]; active: Entry | null; profile: Profile };
export const initialLog = (): Log => ({entries: [], active: null, profile: {name: '', carrier: 'First Due Movers', terminal: '', office: '', vehicle: '', coDriver: '', zone: 'America/Los_Angeles'}});
export function dayKey(t: number, zone: string) { return new Intl.DateTimeFormat('en-CA', {timeZone:zone, year:'numeric',month:'2-digit',day:'2-digit'}).format(t); }
export function localInput(t: number, zone: string) { return new Intl.DateTimeFormat('sv-SE',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(t).replace(' ', 'T'); }
export function epoch(value: string, zone: string) { const target = Date.parse(value+'Z'); let t=target; for(let i=0;i<4;i++){t+=target-Date.parse(localInput(t,zone)+'Z');} if(!Number.isFinite(t)||localInput(t,zone)!==value) throw new Error('This time does not exist in your home-terminal timezone. Choose another time.'); return t; }
export function bounds(day: string, zone: string) { const next = new Date(Date.parse(day+'T12:00Z')+86400000).toISOString().slice(0,10); return [epoch(day+'T00:00', zone), epoch(next+'T00:00', zone)]; }
export function duration(ms: number) { const m=Math.max(0,Math.floor(ms/60000)); return `${Math.floor(m/60)}h ${String(m%60).padStart(2,'0')}m`; }
export function overlaps(a: Entry,b: Entry) { return a.start<(b.end??Infinity)&&b.start<(a.end??Infinity); }
export function validateLog(x: unknown): asserts x is Log {
 const s=x as Log; if(!s||!s.profile||!Array.isArray(s.entries)||s.entries.length>10000) throw new Error('Invalid log.');
 for(const k of ['name','carrier','terminal','office','vehicle','coDriver','zone'] as const) if(typeof s.profile[k]!=='string'||s.profile[k].length>500) throw new Error('Invalid driver details.');
 try{new Intl.DateTimeFormat('en',{timeZone:s.profile.zone}).format();}catch{throw new Error('Invalid timezone.');}
 const rows=[...s.entries,...(s.active?[s.active]:[])]; const ids=new Set<string>();
 for(const e of rows){
  if(!e||typeof e.id!=='string'||e.id.length>100||ids.has(e.id)||!statuses.includes(e.status)||!Number.isFinite(e.start)||e.start<0||e.start>Date.now()+60000) throw new Error('Check the log entry and start time.'); ids.add(e.id);
  if(e===s.active?e.end!==null:(!Number.isFinite(e.end)||e.end!<=e.start||e.end!>Date.now()+60000)) throw new Error('End time must be after start time and not in the future.');
  if(e.miles!==null&&(!Number.isFinite(e.miles)||e.miles<0||e.miles>100000)) throw new Error('Enter a valid distance.');
  if(typeof e.partial!=='boolean'||!['manual','gps'].includes(e.source)) throw new Error('Invalid distance source.');
  for(const k of ['from','to','note'] as const) if(typeof e[k]!=='string'||e[k].length>2000) throw new Error('Text is too long.');
  for(const k of ['document','shipper','commodity'] as const) if(e[k]!==undefined&&(typeof e[k]!=='string'||e[k]!.length>1000)) throw new Error('Text is too long.');
 }
 rows.sort((a,b)=>a.start-b.start); for(let i=1;i<rows.length;i++) if(overlaps(rows[i-1],rows[i])) throw new Error('Duty periods cannot overlap. Adjust the times first.');
}
export function milesBetween(a: Point,b: Point) { const rad=Math.PI/180; const dlat=(b.lat-a.lat)*rad,dlon=(b.lon-a.lon)*rad; const h=Math.sin(dlat/2)**2+Math.cos(a.lat*rad)*Math.cos(b.lat*rad)*Math.sin(dlon/2)**2; return 3958.7613*2*Math.atan2(Math.sqrt(h),Math.sqrt(1-h)); }
