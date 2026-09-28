// supabaseClient.js
// Supabase client initialization using Vite environment variables.
// Ensure @supabase/supabase-js is installed: npm install @supabase/supabase-js

import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
