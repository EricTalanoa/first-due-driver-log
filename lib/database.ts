import { env } from 'cloudflare:workers';
export function database() { if(!env.DB) throw new Error('Storage is unavailable'); return env.DB; }
