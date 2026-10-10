-- Revoke all on settings from anon and authenticated, then grant only what's needed
revoke all on public.settings from anon;
revoke all on public.settings from authenticated;

-- Admin can do everything (governed by RLS policy "admin scrive")
grant all on public.settings to authenticated;

-- But restrict which columns can be updated (exclude paypal credentials)
-- We can't do column-level revokes on GRANT ALL, so we do it explicitly:
revoke update (paypal_client_id, paypal_client_secret, paypal_mode) on public.settings from authenticated;
grant update (budget, max_per_club, max_subs, bonus, squad_p, squad_d, squad_c, squad_a, squad_deadline, market_from, market_to, market_max, subscription_price, subscription_label) on public.settings to authenticated;
grant select on public.settings to authenticated;
grant insert on public.settings to authenticated;
grant delete on public.settings to authenticated;
