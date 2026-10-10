-- Add crest and avatar columns to profiles
alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists crest text default 'auto',
  add column if not exists crest_url text;
