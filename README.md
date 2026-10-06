# Print Sizing

A phone app for printing photos the way your printer's own options won't:

- **Photo sheet:** put several photos on one page (e.g. 6 on A4, or 2 on a 6×4), or print every photo at an **exact size**, such as 2 × 3 in, for cutting out and sticking in. It packs as many as fit, with optional cut guides.
- **Poster:** tile one image across several pages (e.g. 2 × 2 sheets of A4, or exactly 80 cm wide), with trim marks, optional glue overlap and page labels so it's easy to put together.

It makes a PDF at exact physical sizes and hands it to the iPhone share sheet, so you can print with **AirPrint or your printer's own app (HP Smart, Epson, Canon…)**, or save it to Files.

It is a web app (PWA). You add it to your Home Screen, it opens full screen like any other app, and it works offline. You don't need the App Store, a Mac or a developer account. Your photos are never uploaded; everything happens on the phone.

## Getting it onto your iPhone

The app is a set of static files, so it just needs hosting somewhere with HTTPS.

**Option A: GitHub Pages (simplest).** GitHub Pages only works for public repositories, unless you have GitHub Pro.

1. Make this repository public (Settings → General → Danger zone → Change visibility). There's nothing private in the code.
2. Settings → Pages → *Build and deployment* → Source **Deploy from a branch**, Branch **main**, folder **/ (root)** → Save.
3. After a minute it's live at **https://tonybfox.github.io/Print-Sizing/**

**Option B: keep the repo private.** Connect it to [Netlify](https://app.netlify.com/start) or [Cloudflare Pages](https://pages.cloudflare.com/), both free. No build command; the publish directory is the repository root.

Then on the iPhone:

1. Open the address in **Safari**.
2. Tap **Share** → **Add to Home Screen**.

## Using it

### Photo sheet

1. Tap **+ Add** and pick from Photos or Files. You can pick several at once.
2. Under **Size** choose:
   - **Photos per page:** e.g. 6. The app picks the arrangement that shows them largest, turning photos sideways when that makes them bigger.
   - **Exact size:** type a width and height (or tap a preset like 2 × 3 in or 35 × 45 mm passport). Every print comes out exactly that size, and as many as possible are packed per page.
3. Choose the paper (A4, Letter, 6×4, 7×5, A5, A3, custom…). Leave orientation on **Auto** to get the most per page.
4. **Layout** options:
   - **Whole photo** keeps the full picture; **Fill & crop** fills each space exactly.
   - Margin, spacing, cut guides (thin outline or corner marks), and **Fill the page with copies**.
5. Tap a photo, in the preview or the strip, to drag/pinch the crop, rotate it, or print extra copies.
6. Tap **Print…** → **Print or share…** → **Print**.

### Poster

1. Choose an image.
2. Set the size by **Pages** (e.g. 3 across × 2 down), or by finished **Width** or **Height**.
3. Pick paper and margin. Add an **Overlap** if you want a strip to glue under the next page.
4. Print. Each page is labelled (A1, A2, B1…) with a tiny map of where it goes. Trim along the corner marks and join.

### Getting exact sizes

When printing from an iPhone, iOS may shrink the page slightly to fit the printer's unprintable edges. If your 2 × 3 in prints come out a touch small:

1. ⚙︎ Settings → **Printer size check** → **Print test page**.
2. Measure the long line with a ruler, type the length, and tap **Apply**.

From then on the app corrects for it, separately for each paper size. Also pick the right paper size in the print dialog. If your printer app has a scaling option, choose 100% / actual size.

## Development

There's no build step: plain HTML, CSS and ES modules.

```sh
npm run serve      # http://localhost:8080
npm test           # layout maths + PDF writer unit tests (Node 20+)
npm run e2e        # drives the real UI in Chromium (iPhone emulation) and measures the PDFs
```

`npm run e2e` needs Playwright (`npm i -D playwright`) and poppler-utils (`pdfinfo`, `pdftoppm`).

| File | What it does |
| --- | --- |
| `js/layout.js` | Grid choice, exact-size packing, poster tiling (pure functions, unit tested) |
| `js/crop.js` | Crop and rotation maths |
| `js/pdf.js` | Small PDF writer (JPEG images, lines, text) |
| `js/output.js` | Renders each crop at print resolution and builds the PDF; test page |
| `js/render.js` | On-screen preview drawing |
| `js/editor.js` | Crop / rotate / copies editor |
| `js/app.js` | UI wiring and settings |
| `sw.js` | Offline cache. **Bump `VERSION` when releasing** so phones pick up the new files. |
