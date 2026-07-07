# App Review Information — Paper Comic Reader

Paste the "Notes" block into App Store Connect → App Review Information, and **attach
`demo/Inklings.cbz`** in the Attachment field.

- **Sign-in required:** No. The app has no accounts, login, or backend.
- **Demo account:** Not applicable.
- **Contact:** accounts@wiredframe.de

---

## Notes (paste into ASC)

```
Paper Comic Reader is a local, offline reader for comic archive files (CBZ/CBR) that the
user already owns. The app ships with an EMPTY library — it provides no content of
its own — so please import a file first:

HOW TO TEST
1. We have attached a sample comic, "Inklings.cbz" (original artwork, ours, cleared
   for this purpose). Get it onto the device via AirDrop or Finder → Files.
2. In the app, open the Library tab → “…” menu → Import (or the Import button on the
   empty state) → pick Inklings.cbz. It appears in the grid.
3. Tap the cover to read. Swipe to turn pages. Double-tap toggles fit. Rotate to
   landscape to see the optional double-page spread. Tap once to show/hide the
   top/bottom controls.
4. Settings has optional toggles: Paper Effect (warm, print-like rendering), Live
   Text (press-and-hold to select text on a page), Double Page, and Tap to Navigate.
5. Bookmarks: in the reader, add a bookmark; browse them in the Bookmarks tab and tap
   one to jump straight to that page.

IN-APP PURCHASES
The “Tip Jar” (Settings → Leave a Tip) offers one optional consumable tip. It is
pure support — it unlocks NO features and gates NO functionality.

PRIVACY
No accounts, no analytics, no tracking, no network content. Imported comics, reading
progress and bookmarks stay on the device. Export compliance: uses only standard,
exempt encryption (ITSAppUsesNonExemptEncryption = NO).
```

---

## Why a demo file matters

Apps that require user-supplied content are frequently rejected under Guideline 2.1
(App Completeness) when the reviewer opens an empty app and can't exercise it.
Attaching a ready-to-open comic removes that risk. `Inklings.cbz` is original artwork
generated for this project (see `tools/gencomic.swift`), so there are no third-party
rights concerns in the demo or in the screenshots that use it.
