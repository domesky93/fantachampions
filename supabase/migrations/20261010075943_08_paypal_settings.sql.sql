-- Store PayPal credentials in settings
alter table public.settings
  add column if not exists paypal_client_id     text,
  add column if not exists paypal_client_secret  text,
  add column if not exists paypal_mode           text not null default 'sandbox';

update public.settings set
  paypal_client_id = 'AdfkKzl7a8AwCSrmsJ9SPZKvueAySSn9GVY1LPwVi7tDVaaD0GiVuDMnwKDLMVQb5C6D9pt5fYLwuX_K',
  paypal_client_secret = 'EMbRU0jVmn_HwVBasZAkEwL74X64v2-lgrbZir_9a3gdFnNIP5SAvZ7NI06JdJ2ssITDRxShV-CJ2LUS',
  paypal_mode = 'live'
where id = 1;
