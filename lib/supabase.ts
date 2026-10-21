import { createClient } from '@supabase/supabase-js';

// Publishable values: safe in the browser. Row-level security keeps each driver's rows private.
export const SUPABASE_URL = 'https://jtofziwssarbifugqjnn.supabase.co';
export const SUPABASE_KEY = 'sb_publishable_noucvZct2WKRH3RxzuHpAw_i8Ln_JgJ';

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: true, autoRefreshToken: true, flowType: 'pkce' } });
