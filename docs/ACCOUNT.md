# Pitwall-account: contract (iOS, iPadOS, tvOS, macOS)

Zelfde opzet als Bingr, met een eigen Supabase-project.

Inloggen is **verplicht**. Flow: **splash → (geen geldige sessie) inlogscherm → app**. Uitloggen brengt je terug naar het inlogscherm. Zonder Supabase-sleutels in de build toont het inlogscherm "Accounts zijn niet ingesteld in deze build." met **Doorgaan zonder account**.

## Configuratie

- `Pitwall/Core/Account/AccountConfig.swift`: `supabaseURL` en `supabaseAnonKey` (publishable key). Openbaar bedoeld, mogen in de repo.
- Repo-secrets voor de workflow **Backend**: `SUPABASE_ACCESS_TOKEN` en `SUPABASE_PROJECT_REF`. De workflow zet schema, auth-instellingen (redirects `pitwall://**`), de versleutelsleutel `PITWALL_STATE_KEY` en de Edge Function `device-auth` klaar en test ze.
- Optionele function-secrets: `PITWALL_DEVICE_LIMIT` (standaard 10), `PITWALL_LINK_URL` (standaard `pitwall://link`).

## Endpoints (REST, geen SDK)

Elke aanvraag: `apikey: <ANON_KEY>`, `Content-Type: application/json`.

| Wat | Aanvraag |
|---|---|
| Account maken | `POST /auth/v1/signup?redirect_to=pitwall://confirmed` `{email, password, data:{lang}}` |
| Inloggen | `POST /auth/v1/token?grant_type=password` `{email, password}` |
| Vernieuwen | `POST /auth/v1/token?grant_type=refresh_token` `{refresh_token}`; 400/401 = uitloggen, netwerkfout = sessie houden |
| Wachtwoord vergeten | `POST /auth/v1/recover?redirect_to=pitwall://reset` `{email}`; de link opent de app, die `PUT /auth/v1/user {password}` doet |
| Uitloggen | `remove_device` voor dit apparaat, dan `POST /auth/v1/logout`, daarna altijd lokaal wissen |

Sessie (`access_token`, `refresh_token`, `expires_at`, `user.id`, `email`) en de vaste `device_id` staan **alleen op dit apparaat** in de sleutelhanger.

## Edge Function `device-auth`

`POST /functions/v1/device-auth` met `{action, …}`; alles behalve `start` en `poll` met `Authorization: Bearer <access_token>`.

| Actie | Body | Antwoord |
|---|---|---|
| `start` | `{device}` | `{code, poll_secret, url: "pitwall://link?code=…", expires_in: 600, interval: 3}` |
| `poll` | `{code, poll_secret}` | `pending` / `expired` / `approved` + `token_hash` → `POST /auth/v1/verify {type:"magiclink", token_hash}` |
| `approve` | `{code}` | `{ok, device}` of 404 `invalid_code` |
| `register_device` | `{device_id, name, platform}` | `{ok, limit}` of 403 `device_limit` + lijst |
| `heartbeat` | `{device_id}` | `{ok}` of `{revoked:true}` → lokaal uitloggen |
| `list_devices` / `rename_device` / `remove_device` | | zoals Bingr |
| `get_state` / `put_state` / `delete_state` | `{section, data}` | versleuteld (AES-GCM) opgeslagen |
| `delete_account` | `{}` | `{ok}` |

**Wanneer:** na elke login `register_device`; bij starten, terugkeer naar de voorgrond en elke 5 minuten `heartbeat` en daarna de sync.

## Tv-koppeling

Apple TV toont links een QR-code (`pitwall://link?code=K7QMX4`) en de code als `K7Q-4MX`, rechts **Inloggen met e-mail**. De code ververst als hij verloopt. De camera van de telefoon opent Pitwall, die vraagt om te bevestigen (`approve`). Handmatig kan het via **Account › Tv koppelen**.

## Sync (account + iCloud)

Onderdelen, elk als één geheel met `updatedAt` (seconden sinds 1970); de nieuwste wint:

| Section | Inhoud |
|---|---|
| `f1tv` | de F1 TV-sessie (`sessionID`, `subscriptionToken`, naam, e-mail, land, status) of `null` (uitgelogd) |
| `settings` | catalogustaal, commentaartaal, live-start, standaardfeed, kwaliteit, multiview-kwaliteit, voortgang, ondertitels |
| `setups` | opgeslagen multiview-setups |

- **Server:** `put_state {section, data: {updatedAt, value}}`, ongeveer 3 s na een lokale wijziging. Ophalen na login, bij starten, voorgrond en heartbeat.
- **iCloud Key-Value Store:** sleutel `pitwall.sync.<section>` = `{updatedAt, json}`; direct bij een wijziging, en bij een externe iCloud-wijziging meteen toepassen.
- **Ander account op dit apparaat:** de F1 TV-login en setups van het vorige account worden eerst gewist, daarna komt alles van het nieuwe account.
- **Fouten:** altijd stil; lokaal blijft leidend tot er weer verbinding is.
