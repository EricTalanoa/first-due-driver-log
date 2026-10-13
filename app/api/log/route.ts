import { getChatGPTUser } from '../../chatgpt-auth';
import { database } from '../../../lib/database';
import { initialLog, validateLog } from '../../../lib/log';
export const dynamic = 'force-dynamic';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
export async function GET(){
 const user=await getChatGPTUser(); if(!user) return json({error:'Sign in again to access your log.'},401);
 try{ const row=await database().prepare('SELECT data, revision FROM driver_logs WHERE user_id = ?').bind(user.userId).first<{data:string;revision:number}>(); return json({log:row?JSON.parse(row.data):initialLog(),revision:row?.revision??0}); }
 catch(e){console.error('Read log failed',e);return json({error:'Your log could not be loaded. Please retry.'},503);}
}
export async function PUT(request:Request){
 const user=await getChatGPTUser(); if(!user) return json({error:'Sign in again to save your log.'},401);
 const origin=request.headers.get('origin'); if(origin&&origin!==new URL(request.url).origin) return json({error:'Invalid request origin.'},403);
 let body; try{ const raw=await request.text(); if(raw.length>2000000) return json({error:'Log is too large.'},413); body=JSON.parse(raw); validateLog(body.log); if(!Number.isInteger(body.revision)||body.revision<0) throw new Error('Invalid revision.'); }
 catch(e){return json({error:e instanceof Error?e.message:'Invalid entry.'},400);}
 try{
 const db=database(); const data=JSON.stringify(body.log);
 const row=body.revision===0
 ?await db.prepare('INSERT INTO driver_logs (user_id, data, revision) VALUES (?, ?, 1) ON CONFLICT(user_id) DO NOTHING RETURNING revision').bind(user.userId,data).first<{revision:number}>()
 :await db.prepare('UPDATE driver_logs SET data = ?, revision = revision + 1 WHERE user_id = ? AND revision = ? RETURNING revision').bind(data,user.userId,body.revision).first<{revision:number}>();
 if(!row) return json({error:'Your log changed in another tab or device. Reload before saving; your open form is still here.'},409);
 return json({revision:row.revision});
 }catch(e){console.error('Save log failed',e);return json({error:'Not saved. Check your connection and try again. Your entry is still here.'},503);}
}
