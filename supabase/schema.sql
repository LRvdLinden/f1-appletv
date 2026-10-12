-- Pitwall-accounts (zie docs/ACCOUNT.md). Alleen de Edge Function (service role) leest en schrijft;
-- RLS zonder policies houdt alle anderen buiten. Het script is idempotent en draait bij elke deploy.

-- Tv-koppelcodes (QR / code op Apple TV)
create table if not exists public.device_codes (
  code        text primary key,
  poll_secret text not null,
  device      text,
  user_id     uuid references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
alter table public.device_codes enable row level security;
revoke all on public.device_codes from anon, authenticated;
create index if not exists device_codes_expires_idx on public.device_codes (expires_at);

-- Gekoppelde apparaten per account
create table if not exists public.account_devices (
  user_id      uuid not null references auth.users(id) on delete cascade,
  device_id    text not null,
  name         text not null default '',
  platform     text not null default '',
  custom_name  boolean not null default false,
  session_id   uuid,
  created_at   timestamptz not null default now(),
  signed_in_at timestamptz,
  last_seen_at timestamptz not null default now(),
  primary key (user_id, device_id)
);
alter table public.account_devices enable row level security;
revoke all on public.account_devices from anon, authenticated;

-- Sessie van een verwijderd apparaat intrekken, zodat het apparaat uitlogt.
create or replace function public.revoke_session(sid uuid) returns void
language sql security definer set search_path = auth, public as $$
  delete from auth.sessions where id = sid;
$$;
revoke all on function public.revoke_session(uuid) from public, anon, authenticated;
grant execute on function public.revoke_session(uuid) to service_role;

-- Accountgegevens per onderdeel (f1tv, settings, setups), versleuteld (AES-GCM) door de Edge Function.
create table if not exists public.account_state (
  user_id    uuid not null references auth.users(id) on delete cascade,
  section    text not null,
  data       text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, section)
);
alter table public.account_state enable row level security;
revoke all on public.account_state from anon, authenticated;

-- Wachtwoord gewijzigd: alle sessies en gekoppelde apparaten vervallen.
create or replace function public.pitwall_on_password_change() returns trigger
language plpgsql security definer set search_path = public, auth as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    delete from auth.sessions where user_id = new.id;
    delete from public.account_devices where user_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists pitwall_password_change on auth.users;
create trigger pitwall_password_change after update of encrypted_password on auth.users
  for each row execute function public.pitwall_on_password_change();
