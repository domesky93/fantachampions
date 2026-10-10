-- Fix: revoke execute on security definer functions from anon
revoke execute on function public.check_lineup_in_squad() from anon;
revoke execute on function public.save_squad(bigint[]) from anon;
revoke execute on function public.save_lineup(int, text, jsonb) from anon;

-- Fix: set search_path on functions with mutable search_path
alter function public.module_counts(text) set search_path = public;
alter function public.fantavoto(votes, character, jsonb) set search_path = public;
