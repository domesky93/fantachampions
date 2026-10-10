-- Create a view for public settings that excludes PayPal secrets
create or replace view public.settings_public with (security_invoker = true) as
  select id, budget, max_per_club, max_subs, bonus,
         squad_p, squad_d, squad_c, squad_a, squad_deadline,
         market_from, market_to, market_max,
         subscription_price, subscription_label
  from public.settings;

grant select on public.settings_public to authenticated;
revoke select on public.settings from authenticated, anon;
