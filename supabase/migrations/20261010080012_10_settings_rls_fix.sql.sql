-- Fix settings RLS: only admin can access the raw table, everyone reads via view
drop policy if exists "lettura" on public.settings;
create policy "settings admin only" on public.settings for select to authenticated
  using (public.is_admin());
-- Keep the existing admin write policy (it was created by the loop in 03_security.sql)
