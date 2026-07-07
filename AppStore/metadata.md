# App Store Connect — Metadata (Paper Comic Reader 1.0.0)

Ready-to-paste listing content. Character limits are noted per field; counts are
approximate — verify in App Store Connect (ASC), which enforces them.

> Everything here can be prepared now. Entering it into ASC and reserving the app
> name needs the Developer account to be **active** (currently enrollment pending).

---

## 0. Decisions still open (need your call)

- **App name** — ✅ decided: **Paper Comic Reader** (§1). Confirm it's available when
  you reserve it in ASC; a fallback is noted there.
- **Primary language** — draft is **English** (matches the in-app UI). A German
  localization of the key fields is in §7. Decide whether DE is a second locale or
  the primary.
- **Support / Privacy Policy URLs** — must be live before submission (§8).

---

## 1. Name  (max 30 characters)

**Chosen:** `Paper Comic Reader` (18 characters).

Three high-value terms in one natural phrase — *Paper* (brand / USP), *Comic*
(category) and *Reader* (function). Confirm it's free of conflicts when you reserve
it in ASC; keep a fallback like `Paper Comic: CBZ & CBR` in reserve.

> The in-app display name (`CFBundleDisplayName`) is also set to **Paper Comic
> Reader**. iOS truncates it under the icon (~"Paper Comic…"); shorten it to
> `Paper Comic` if you want a clean home-screen label.

## 2. Subtitle  (max 30 characters)

The name already carries *comic / reader / paper*, so let the subtitle add **new**
keywords (cbz, cbr, manga):

- `CBZ, CBR & manga library` (24)  ← recommended
- `Your CBZ, CBR & manga shelf` (27)
- `Offline CBZ, CBR & manga` (24)

## 3. Promotional text  (max 170, editable anytime without review)

```
A fast, private comic reader for CBZ and CBR — smooth page turns, a paper-like
reading mode, bookmarks with thumbnails, and no tracking whatsoever.
```

## 4. Keywords  (max 100 chars, comma-separated, no spaces)

```
rar,zip,viewer,webtoon,graphic,novel,book,panel,pages,bookmark,offline,ebook,scan
```

Notes: don't repeat words already in the **name** (paper, comic, reader) or the
**subtitle** (cbz, cbr, manga, library) — ASC indexes name + subtitle + keywords
together, so repeats waste the 100-char budget. Singular forms are fine (plurals are
matched). Trim to ≤100 chars in ASC.

## 5. Description  (max 4000)

```
Paper Comic Reader is a fast, private, native reader for your CBZ and CBR comics. No
account, no cloud, no ads, no tracking — just your comics, on your device.

BUILT FOR READING
• Open CBZ (ZIP) and CBR (RAR) archives instantly.
• Full-screen, paged reader tuned for smooth, high-frame-rate page turns.
• Double-tap to switch fit — fit-width or fit-height — with no drifting.
• Double-page spreads in landscape, with cover-first pairing that keeps facing
  pages aligned.
• Optional tap-to-navigate: step through a page in thirds, then turn.
• Resumes exactly where you left off.

A LIBRARY YOU CONTROL
• Every comic in one clean cover grid, with reading progress at a glance.
• Gallery or list view, adjustable cover size, and a “surprise me” random pick.
• Global bookmarks with page thumbnails — jump straight back to any moment.

READS LIKE PAPER (OPTIONAL)
• A tasteful paper effect renders pages with a warm, printed-ink feel instead of a
  harsh backlit screen. Toggle it any time.

SELECT TEXT
• Live Text lets you press and hold to select text directly on the page.

PRIVATE BY DESIGN
• No analytics, no tracking, no accounts. Your comics, reading progress and
  bookmarks never leave your device.

Paper Comic Reader is free. If you’d like to support development, there’s an optional tip
jar — it unlocks nothing and asks for nothing.
```

## 6. What's New in This Version  (1.0.0)

```
First release. Thanks for reading!

• Open CBZ and CBR comics
• Smooth, full-screen paged reader with double-page landscape mode
• Library with reading progress, bookmarks, and a random picker
• Optional paper reading effect and Live Text
• Private by design — no tracking, no accounts
```

---

## 7. German localization (de-DE) — key fields

- **Subtitle:** `CBZ- & CBR-Comics lesen` (23)
- **Keywords:** `comic,cbz,cbr,leser,manga,rar,zip,bibliothek,lesezeichen,offline,buch,seiten`
- **Promotional text:**
  ```
  Ein schneller, privater Comic-Reader für CBZ und CBR — flüssiges Umblättern, ein
  papierartiger Lesemodus, Lesezeichen mit Vorschau und keinerlei Tracking.
  ```
- **Description:**
  ```
  Paper Comic Reader ist ein schneller, privater, nativer Reader für deine CBZ- und
  CBR-Comics. Kein Konto, keine Cloud, keine Werbung, kein Tracking — nur deine
  Comics, auf deinem Gerät.

  ZUM LESEN GEMACHT
  • Öffnet CBZ- (ZIP) und CBR-Archive (RAR) sofort.
  • Vollbild-Reader mit flüssigem Umblättern bei hoher Bildrate.
  • Doppeltippen wechselt die Ansicht — Breite oder Höhe — ohne Verrutschen.
  • Doppelseiten im Querformat mit sinnvoller Paarung ab dem Cover.
  • Optionale Tipp-Navigation: in Dritteln durch die Seite, dann umblättern.
  • Setzt genau dort fort, wo du aufgehört hast.

  EINE BIBLIOTHEK, DIE DIR GEHÖRT
  • Alle Comics in einem klaren Cover-Raster mit Lesefortschritt.
  • Galerie oder Liste, verstellbare Covergröße und ein Zufalls-Picker.
  • Globale Lesezeichen mit Seitenvorschau.

  LIEST SICH WIE PAPIER (OPTIONAL)
  • Ein dezenter Papiereffekt lässt Seiten warm wie gedruckte Tinte wirken statt
    grell hinterleuchtet. Jederzeit umschaltbar.

  TEXT AUSWÄHLEN
  • Live Text: Text direkt auf der Seite per Gedrückthalten auswählen.

  PRIVAT VON GRUND AUF
  • Kein Tracking, keine Analyse, keine Konten. Deine Comics, dein Lesefortschritt
    und deine Lesezeichen verlassen nie dein Gerät.

  Paper Comic Reader ist kostenlos. Wer die Entwicklung unterstützen möchte, findet ein
  optionales Trinkgeld — es schaltet nichts frei und verlangt nichts.
  ```

---

## 8. URLs & general

- **Support URL:** e.g. `https://wiredframe.de/comicreader` (must be live; a simple
  page with a contact email is enough — `accounts@wiredframe.de`).
- **Marketing URL:** optional.
- **Privacy Policy URL:** required. The text already exists in-app (Settings → Privacy
  Policy). Host the same text at a stable URL (e.g. `https://wiredframe.de/comicreader/privacy`).
- **Copyright:** `2026 Ulf Schuster (Wiredframe)`
- **Primary category:** Books · **Secondary:** Entertainment
- **Contact email (App Review):** `accounts@wiredframe.de`

## 9. Age rating

All content-descriptor answers are **None** → expected rating **4+**.

- Cartoon/Fantasy Violence, Realistic Violence, Sexual Content, Profanity, Horror,
  Mature/Suggestive, Alcohol/Tobacco/Drugs, Gambling, Contests: **None**
- Unrestricted Web Access: **No** (the app has no browser/network)
- Made for Kids: **No**

> Note: the app displays comics the user imports themselves; it provides no content
> and has no sharing/social features, so 4+ is appropriate. If you expect users to
> import mature comics and prefer to signal that, you can self-select a higher band.

## 10. In-App Purchase (Tip Jar)

**One Consumable** tip (created in ASC). Its ID, name and description match the app
and `Tips.storekit`:

| Product ID | Display Name | Description | Price |
|---|---|---|---|
| `de.wiredframe.comicreader.tip.small` | Tip | A one-time thank-you | €4.99 / $3.99 |

- Type: **Consumable** · not family-shareable. The `.small` suffix is the original,
  immutable product ID — it is now the only tip.
- Set the ASC **display name** to what users should see (e.g. `Tip` or `Leave a Tip`).
- Needs one review screenshot in ASC (a capture of the Tip Jar sheet).

## 11. Build / export compliance

- Marketing version **1.0.0**, build **1**.
- `ITSAppUsesNonExemptEncryption = NO` is baked into the Info.plist (post-build
  script), so ASC will **skip the encryption question** on upload.
- Uploading the build needs distribution signing → your active Team ID.

## 12. App Review notes

See `AppReviewNotes.md`. Key point: attach the demo comic (`demo/Inklings.cbz`) so
the reviewer can actually open something — the app is empty until a file is imported.
