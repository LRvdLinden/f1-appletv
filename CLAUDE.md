# Pitwall: werkafspraken

- Versie blijft 1.0.0; elke nieuwe build verhoogt het buildnummer: `python3 Tools/generate_project.py <build>`.
- iOS/iPadOS, tvOS en macOS gaan altijd samen mee (één multiplatform-target). GitHub Actions bouwt ze bij elke push naar `main`.
- Bij elke build: Xcode-zip opleveren, en de repo volledig bijwerken (README, CHANGELOG.md, screenshots waar nodig).
- Accounts (Supabase): contract in `docs/ACCOUNT.md`, backend in `supabase/`, deploy via de workflow `Backend`.
- Geheime sleutels nooit in de repo; de repo is openbaar. De Supabase-URL en publishable key mogen er wel in (`AccountConfig.swift`).
- Bundle-ID `nl.lrvdlinden.pitwall`, team `EU3UY476T6`.
