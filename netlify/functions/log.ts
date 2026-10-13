import { getStore } from '@netlify/blobs';
import { authenticated,json,sameOrigin } from '../shared/auth';
import { initialLog,validateLog } from '../../lib/log';
export default async function handler(request:Request){
 if(!authenticated(request))return json({error:'Unlock your private log to continue.'},401);
 if(!['GET','PUT'].includes(request.method))return json({error:'Method not allowed'},405);
 if(!sameOrigin(request))return json({error:'Invalid origin'},403);
 try{
  const store=getStore({name:'private-driver-log',consistency:'strong'});
  if(request.method==='GET'){const row=await store.getWithMetadata('log',{type:'json'});return json({log:row?.data??initialLog(),revision:row?.etag??null});}
  const raw=await request.text();if(raw.length>2000000)return json({error:'Log is too large.'},413);
  let b;try{b=JSON.parse(raw);validateLog(b.log);if(b.revision!==null&&(typeof b.revision!=='string'||b.revision.length>200))throw new Error('Invalid revision.');}catch(e){return json({error:e instanceof Error?e.message:'Invalid entry'},400);}
  const result=await store.setJSON('log',b.log,b.revision?{onlyIfMatch:b.revision}:{onlyIfNew:true});
  if(!result.modified)return json({error:'Your log changed in another tab or device. Reload before saving; your open form is still here.'},409);
  return json({revision:result.etag});
 }catch(e){console.error('Log storage failure',e instanceof Error?e.message:'Unknown');return json({error:'Your log could not be saved or loaded. Check your connection and try again. Your open entry is still here.'},503);}
}
