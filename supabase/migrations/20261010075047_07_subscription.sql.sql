-- ============================================================
-- SISTEMA ABBONAMENTO 25€ PAYPAL
-- ============================================================

-- Aggiunge colonne abbonamento al profilo
alter table public.profiles
  add column if not exists subscription_paid     boolean     not null default false,
  add column if not exists subscription_paid_at  timestamptz,
  add column if not exists paypal_order_id       text;

-- subscription_paid NON è scrivibile dall'utente: 
-- la colonna non è inclusa nei grant UPDATE (solo username, team_name lo sono).
-- L'aggiornamento avviene solo via edge function con service role key.

-- Impostazione prezzo abbonamento
alter table public.settings
  add column if not exists subscription_price  numeric(10,2) not null default 25.00,
  add column if not exists subscription_label  text          not null default 'Abbonamento Champions 2026/27';

update public.settings set subscription_price = 25.00, subscription_label = 'Abbonamento Champions 2026/27' where id = 1;

-- Funzione per verificare lo stato abbonamento (pubblica tra authenticated)
create or replace function public.is_subscribed()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select subscription_paid from public.profiles where id = auth.uid()), false);
$$;

revoke all on function public.is_subscribed() from public, anon;
grant execute on function public.is_subscribed() to authenticated;

-- Funzione per marcare l'abbonamento come pagato (chiamata solo dalla edge function con service role)
create or replace function public.mark_subscription_paid(p_uid uuid, p_order_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
    set subscription_paid = true,
        subscription_paid_at = now(),
        paypal_order_id = p_order_id
    where id = p_uid;
end;
$$;

revoke all on function public.mark_subscription_paid(uuid, text) from public, anon, authenticated;
