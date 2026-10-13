import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
export const json=(value:unknown,status=200,headers:Record<string,string>={})=>Response.json(value,{status,headers:{'Cache-Control':'no-store',...headers}});
export function allowed(pin:string){const expected=process.env.DRIVER_LOG_PIN_HASH;if(!expected||!/^[a-f0-9]{64}$/.test(expected)||!/^\d{4}$/.test(pin))return false;return timingSafeEqual(createHash('sha256').update(pin).digest(),Buffer.from(expected,'hex'));}
function signature(value:string){const secret=process.env.DRIVER_LOG_SESSION_SECRET;if(!secret)throw new Error('Session configuration unavailable');return createHmac('sha256',secret).update(value).digest('hex');}
export function newSession(){const value=`${randomBytes(24).toString('base64url')}.${Date.now()+86400000}`;return `${value}.${signature(value)}`;}
export function authenticated(request:Request){
 const cookie=request.headers.get('cookie')??'';const token=cookie.split(';').map(p=>p.trim()).find(p=>p.startsWith('driver_access='))?.slice(14)??'';
 const parts=token.split('.');if(parts.length!==3||!/^\d+$/.test(parts[1])||!/^[a-f0-9]{64}$/.test(parts[2])||Number(parts[1])<Date.now())return false;
 try{return timingSafeEqual(Buffer.from(signature(parts[0]+'.'+parts[1]),'hex'),Buffer.from(parts[2],'hex'));}catch{return false;}
}
export function sameOrigin(request:Request){const origin=request.headers.get('origin');return !origin||origin===new URL(request.url).origin;}
export function sessionCookie(token:string,url:string,maxAge?:number){return `driver_access=${token}; HttpOnly; SameSite=Strict; Path=/${maxAge===0?'; Max-Age=0':''}${new URL(url).protocol==='https:'?'; Secure':''}`;}
