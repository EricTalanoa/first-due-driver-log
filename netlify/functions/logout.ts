import { json,sameOrigin,sessionCookie } from '../shared/auth';
export default async function handler(request:Request){if(request.method!=='POST')return json({error:'Method not allowed'},405);if(!sameOrigin(request))return json({error:'Invalid origin'},403);return json({ok:true},200,{'Set-Cookie':sessionCookie('',request.url,0)});}
