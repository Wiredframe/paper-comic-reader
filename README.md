# Comic Reader (iOS)

A lean, performant native comic reader for iPhone & iPad (SwiftUI + Core Image /
Metal). It opens **CBZ and CBR** archives, keeps a library with reading progress
and bookmarks, and can render pages with a realistic **paper effect** (ported from
the Simple Comic fork) so they read like ink on paper instead of a backlit screen.

## Project setup

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` (so file/target changes are easy to review and merge).

```bash
brew install xcodegen        # once
xcodegen generate            # regenerate ComicReader.xcodeproj after editing project.yml
open ComicReader.xcodeproj   # or build from the command line:
xcodebuild -project ComicReader.xcodeproj -scheme ComicReader \
  -destination 'generic/platform=iOS Simulator' build
```

The generated `.xcodeproj` can be opened directly in Xcode without XcodeGen — you
only need XcodeGen when you change `project.yml`. Signing is `Sign to Run Locally`
(`-`), so no Apple account is required for the Simulator.

- **Deployment target:** iOS 18 · **Bundle id:** `de.wiredframe.comicreader`

## Structure

```
ComicReader/
  App/            ComicReaderApp (@main, SwiftData container) · RootTabView (floating tab bar)
  Archive/        ComicArchive protocol + ZipComicArchive (ZIPFoundation) / RarComicArchive (UnrarKit)
  Model/          SwiftData models (ComicBook, Bookmark, Folder) · Storage · ImageDownsampler · Importer
  Library/        Recents / Collection / Bookmarks tabs, cover grid, folders, gallery/list, import
  Reader/         UIKit paged, zoomable reader core + SwiftUI chrome, page grid, bookmarks
  PaperEffect/    Platform-neutral paper engine (PaperFilter + PaperKernels.metal) + settings
  Settings/       Reader / paper / library settings
  Resources/      Assets.xcassets (AppIcon + AccentColor)
Vendor/UnrarKit/  Vendored UnrarKit + unrar engine (CBR; no clean SPM package exists)
```

### Formats / persistence

- **CBZ** via [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (SPM).
- **CBR** via [UnrarKit](https://github.com/abbeycode/UnrarKit), vendored flat under
  `Vendor/UnrarKit` (unrar C++ compiled with `-DSILENT -DRARDLL`; see `project.yml`
  for the exact source/exclude list). Reached from Swift via the bridging header.
- **Library** is a [SwiftData](https://developer.apple.com/xcode/swiftdata/) store;
  archives, covers and bookmark thumbnails are files on disk (see `Storage`).

### The reader

Full-bleed paged UIKit core — a horizontal, paging `UICollectionView`
(`ReaderCollectionController`) of `ReaderPageCell`s — wrapped for SwiftUI. There is
no pinch zoom: a **double-tap toggles the fit** instead (single page: fit-width ⇄
fit-height), which keeps the layout drift-free. In landscape, an optional **double
page** mode shows two pages side by side with a *fixed* pairing (cover alone, then
2·3, 4·5 …, so a right-half page never becomes a left half); a double-tap there
focuses the tapped page at fit-width. Rotation re-fits the page animated. An optional
"page-by-page" mode taps through the page in thirds. Resumes on the last read page and
has a page-grid picker. Bookmarks (page screenshots) are added from the reader and
browsed globally in the **Bookmarks tab** — tapping one opens that comic straight to
the page.

### The paper effect

`PaperFilter` is engine-only and reusable: a warm-cream tonal remap plus an even,
isotropic paper grain (`PaperKernels.metal`) laid over the page two ways — a multiply
"body" plus a screen "show-through". Falls back to pure Core Image if the Metal
kernel can't load. Global on/off switch in Settings.

> The kernel needs the Metal toolchain to build. On Xcode 26 that's a one-time
> `xcodebuild -downloadComponent MetalToolchain`.

## Roadmap (priority order)

Goal above everything: **stay lean and fast**; panel detection must run on-device as
efficiently and battery-friendly as possible.

1. **Reader foundation** — ✅ open CBZ/CBR, library with folders, paged zoomable
   reader, resume, global bookmarks with thumbnails, page-grid picker, paper effect.
2. **Live Text / OCR** — native VisionKit Live Text (press-and-hold to select) is
   toggleable in Settings; deeper OCR (copy / speak, cached per page) comes next.
3. **Panel detection & smart zoom** — detect panels once per page (cache the rects),
   then guided zoom. Don't over-zoom: the priority is only that the target panel is
   in view, and *equally* that the comic fills the **full screen width** whenever
   possible. Adjustable min/max, hysteresis; detection downscaled on a background queue.
4. **Random comic** — ✅ surprise-me picker (Collection & Bookmarks toolbars).
5. **Double-page (landscape) layout** — ✅ global toggle, fixed pairing.

Feature status: reader foundation ✅ · paper effect ✅ · Live Text setting ✅ ·
double-page ✅ · random comic ✅.

_Out of scope (dropped): library search, OPDS, metadata/backstories. A page-curl
open/close transition was prototyped and removed; it may be redone later._
