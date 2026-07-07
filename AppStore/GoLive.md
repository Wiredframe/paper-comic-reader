# Go-Live checklist — Paper Comic Reader 1.0.0

Ordered path to a submitted app, now that the Developer account is active. Legend:
**[You]** = App Store Connect web UI / Xcode · **[Claude]** = prepared in this repo.

Paste-ready text lives in `metadata.md`; review notes in `AppReviewNotes.md`;
screenshots in `screenshots/`; the reviewer demo in `demo/Inklings.cbz`.

---

## A. App Store Connect — create the app  [You]

1. **Bundle ID** — usually auto-registered on first upload. If you want it up front:
   developer.apple.com → Certificates, IDs & Profiles → Identifiers → `+` →
   App IDs → App → Bundle ID `de.wiredframe.comicreader` (no special capabilities
   needed; In-App Purchase is on by default).
2. **New app** — App Store Connect → Apps → `+` → New App:
   - Platform **iOS**, Bundle ID `de.wiredframe.comicreader`
   - **Name** — pick from `metadata.md` §1 (this reserves it; alternates ready if taken)
   - Primary language, SKU (e.g. `comicreader`), Full access.
3. **In-App Purchase** — Features → In-App Purchases → `+` → **Consumable** (one tip),
   with the ID / name / price in `metadata.md` §10. Its required review screenshot is
   ready at `screenshots/iap-review/tip-jar.png`. It submits with the first version.

## B. Xcode — archive & upload the build  [You, Claude preps signing]

4. Xcode → **Settings → Accounts** → add your Apple ID (lets Xcode create the
   Apple Distribution certificate automatically).
5. Signing is set to **Automatic + your Team** in `project.yml` (Claude wires this
   once you share the Team ID; then `xcodegen generate`).
6. Destination: **Any iOS Device (arm64)**.
7. **Product → Archive.**
8. Organizer → **Distribute App → App Store Connect → Upload** → keep automatic
   signing → Upload. (Version 1.0.0, build 1.)
9. Wait for "processing" to finish (ASC → your app → TestFlight/Activity, ~5–30 min;
   you'll get an email).

## C. App Store Connect — the 1.0.0 version page  [You]

10. **Description / Keywords / Subtitle / Promotional text** — from `metadata.md`
    §2–5 (and §7 for a German localization if you add de-DE).
11. **Screenshots** — upload from `screenshots/iphone-6.9/` and `screenshots/ipad-13/`
    (6.9″ iPhone + 13″ iPad both required for a universal app).
12. **What's New** — `metadata.md` §6.
13. **Promotional / Support / Privacy Policy URLs** — `metadata.md` §8. The Privacy
    Policy text already exists in-app; host it at a stable URL first.
14. **General → Category** — Books (primary), Entertainment (secondary). **Copyright**
    `2026 Ulf Schuster (Wiredframe)`.
15. **Age Rating** — answer all descriptors *None* → 4+ (`metadata.md` §9).
16. **App Privacy** — "Data Not Collected" (no tracking, no analytics, all on-device).
17. **App Review Information** — paste the notes from `AppReviewNotes.md` and
    **attach `demo/Inklings.cbz`**; contact `accounts@wiredframe.de`.
18. **Build** — select the processed build (from step B).
19. **Pricing and Availability** — Free; choose territories.
20. **Export compliance** — no prompt: `ITSAppUsesNonExemptEncryption = NO` is already
    in the build.
21. Attach the tip IAP to this version (first submission ships it together).
22. **Add for Review → Submit.**

---

## Still open (decide before submitting)

- **App name** — confirm the final choice / availability (`metadata.md` §0, §1).
- **Support + Privacy Policy URLs** must be live.
- **Team ID** — share it so signing can be wired (§B5).

## Nice-to-have before or after 1.0

- Landscape **double-page** screenshot (marquee feature; not yet auto-captured).
- Optional marketing polish: device frames + caption headlines on the screenshots.
