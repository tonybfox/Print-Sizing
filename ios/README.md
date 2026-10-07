# Print Sizing for iPhone (native app)

**Status:** runs in the iOS Simulator. Photo sheets, posters, the photo editor, settings, printing and Share PDF all work, following the design below. Printing has only been checked as far as the iPhone print screen (paper, orientation and preview are right); it still needs a real print on the Epson ET-2850 and a run with Xcode's Printer Simulator.

```sh
cd ios
swift test        # layout engine tests, no Xcode project needed
xcodegen          # regenerate PrintSizing.xcodeproj after adding or removing files
open PrintSizing.xcodeproj
```

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The generated project is committed so Xcode can open it directly.

### Code layout

- `PrintSizing/Layout`: the layout engine (plain Swift, unit tested by `PrintLayoutTests`).
- `PrintSizing/Model`: settings (JSON in `UserDefaults`), photos (original data plus a 1200 px preview) and `AppModel`, which builds the plan and the captions.
- `PrintSizing/Drawing`: draws a `Page` into any Core Graphics context. The preview, printing and the PDF all use it.
- `PrintSizing/Printing`: decoding at print resolution, the `UIPrintPageRenderer`, paper choice and the PDF.
- `PrintSizing/Views`: SwiftUI screens.

## Why native

The web version could only make a PDF and hand it to the share sheet. You had to tap Print → Print or share → Print before seeing the iPhone print settings. iOS then picked the paper and scaling itself.

The native app prints directly: one tap opens the iPhone print screen with the right paper already chosen, and pages are drawn at true size.

## Printing design

- Use `UIPrintInteractionController.shared` with a custom `UIPrintPageRenderer`. Don't print a PDF or use `printingItem`, because then iOS lays the content out itself.
- **Renderer**
  - `numberOfPages = pages.count`.
  - Override `drawPage(at:in:)` and draw the `Page` from the top-left of `paperRect` at `ptPerMM` (72 pt per inch). That is actual size, with no scaling.
  - If `paperRect`'s orientation differs from the page's, turn it a quarter: `translateBy(x: paper.width, y: 0)`, then `rotate(by: .pi / 2)`.
  - If the paper is slightly different (e.g. 10×15 cm loaded for a 6×4 in layout), centre the page on it.
- **`printInteractionController(_:choosePaper:)`**
  - Pick the paper whose size matches the layout page in either orientation, within ±4 pt.
  - Prefer a bordered paper (`printableRect` smaller than the paper) unless the margin is 0; with a 0 margin, prefer a borderless one. Epson borderless printing enlarges the image slightly, which would break exact sizes.
  - Fall back to `UIPrintPaper.bestPaper(forPageSize:withPapersFrom:)`.
- **`UIPrintInfo`**
  - `outputType` is `.photo` when **Photo paper** is on, otherwise `.general`. Photo paper is on by default for photo-paper sizes.
  - `orientation` follows the page, `duplex = .none`, and set a job name.
- **Images**
  - Keep each photo's original `Data`, plus a preview `CGImage` of at most 1200 px.
  - For printing, decode with ImageIO's thumbnail API (`kCGImageSourceCreateThumbnailWithTransform` applies EXIF orientation). Decode at `requiredLongSide(item:imageWidth:imageHeight:dpi:)` for 300 dpi, and cache per photo for the print job.
- **Drawing a placed photo**
  - Crop the `CGImage` to `sourceRect(item.crop, rotation: item.userRot)` × its pixel size.
  - Clip to the destination rectangle, translate to its centre, rotate by `userRot + rot` degrees, then `scaleBy(x: 1, y: -1)`.
  - `ctx.draw(cropped, in:)` a rectangle centred on the origin. Swap its width and height when the total rotation is 90 or 270.
- **Marks:** draw lines and rectangles in gray. Draw text with UIKit string drawing, where the top is the baseline `y` minus `font.ascender`.
- **Share PDF** is a secondary button. Use `UIGraphicsPDFRenderer` with the same page drawing, for saving to Files or a printer app.
- **Testing:** use Xcode's Printer Simulator (Additional Tools for Xcode) to check paper choice and sizes, then a real Epson ET-2850 over AirPrint.

## UI (SwiftUI, iOS 17+)

Mirrors the web app (`index.html`, `js/app.js`).

- **Top bar:** Photo sheet / Poster switch, plus a settings gear. Settings has units (in / cm / mm), quality (200 / 300 dpi) and printing tips.
- **Preview pane** (about 38% of the height)
  - Photo sheet: swipe between pages; tap a photo to edit it.
  - Poster: the assembled poster with page seams, overlap strips and A1/B2 labels.
- **Bottom bar:** "N pages · paper", a Share PDF button and a prominent **Print** button.
- **Photo sheet controls**
  - **Photos:** a row with a Photos button (PhotosPicker, multiple), a Files button (`.fileImporter`) and the thumbnails.
  - **Size:** either *Photos per page* (stepper plus quick chips 1, 2, 3, 4, 6, 8, 9, 12, 16, 20), or *Exact size*. Exact size has width/height fields, presets (`SizePreset.all`), swap, units and "Match each photo's shape".
  - **Paper:** paper size (`Papers.all` plus custom) and orientation (Auto / Portrait / Landscape).
  - **Layout:** Whole photo or Fill & crop, "Turn photos to fit best", margin, spacing, cut guides (none / outline / marks), "Fill the page with copies".
  - **Printer:** the Photo paper toggle. Footer: a 0 margin means borderless where the printer supports it.
- **Poster controls**
  - Image picker.
  - Size by *Pages* (across and down steppers, plus "Fill every page"), *Width* or *Height*.
  - Paper, margin, overlap, "Trim marks & labels", and a how-to-assemble note.
- **Photo editor** (sheet)
  - Shows the rotated preview with a crop window: drag to move, pinch or slider to zoom (use `clampAdjust`). Rotate left/right resets the crop. Also copies and remove.
  - Cropping only applies when the photo is actually cropped: Fill & crop on a sheet, or Fill every page on a poster. The window's aspect is that of the photo's first placed item (`rot ≠ 0 ? h/w : w/h`), or `posterW / posterH` for a poster.
- **Defaults:**
  - Paper and units: A4 (Letter in the US) and inches.
  - Photos per page: 6 per page, whole photo.
  - Exact size: 2 × 3 in, fill & crop, outline cut guides.
  - Spacing: 5 mm margin and 3 mm gap.
  - Settings are saved as JSON in `UserDefaults`.
- **Captions,** as in the web app:
  - Photos per page: "6 per page (2 × 3) · each up to 3.88 × 3.69 in".
  - Exact size: "11 per page · each 2 × 3 in · some turned to fit more".
  - Poster: "Finished size 80 × 60 cm · 3 across × 4 down".
  - Errors: margins too big, piece won't fit (with the room available), too many pages.

## Project setup

- `project.yml` → `PrintSizing.xcodeproj`: iOS App with SwiftUI, deployment target iOS 17, Swift 5 language mode.
  - Bundle ID `com.tonybfox.PrintSizing`, automatic signing, iPhone portrait. Choose your team in Signing & Capabilities to run on a phone.
  - Every file under `PrintSizing/`, including `Layout/`, is an app source.
- **App icon:** `Assets.xcassets/AppIcon.appiconset/icon-1024.png`, rendered from `../icons/icon.svg` with square corners and no alpha.
