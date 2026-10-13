import { allowed, json, sameOrigin, sessionCookie, newSession } from '../shared/auth';
export const config={rateLimit:{windowLimit:10,windowSize:60,aggregateBy:['ip','domain']}};
export default async function handler(request:Request){
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 if(!sameOrigin(request))return json({error:'Invalid origin'},403);
 try{const raw=await request.text();if(raw.length>300)return json({error:'Enter your four-digit passcode.'},400);const {pin}=JSON.parse(raw);if(typeof pin!=='string'||!allowed(pin))return json({error:'Incorrect passcode. Please try again.'},401);return json({ok:true},200,{'Set-Cookie':sessionCookie(newSession(),request.url)});}catch{return json({error:'Could not unlock. Please try again.'},400);}
}
