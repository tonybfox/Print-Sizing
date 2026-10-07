import Foundation

// One image tiled across several pages. Port of js/layout.js (buildPoster).

enum PosterSizeBy: String, Codable, CaseIterable {
    case grid, width, height
}

struct PosterOptions {
    var paper: MMSize
    var orientation: PageOrientation = .auto
    var margin: Double = 6
    /// Strip repeated on the next page, for gluing under.
    var overlap: Double = 0
    var sizeBy: PosterSizeBy = .grid
    var cols: Int = 2
    var rows: Int = 2
    var width: Double = 600
    var height: Double = 800
    /// With sizeBy == .grid: crop the image to fill every page.
    var fill: Bool = false
    var guides: Bool = true
    var photo: PhotoRef?
}

struct PosterInfo: Hashable {
    var orientation: PageOrientation
    var page: MMSize
    var posterW: Double
    var posterH: Double
    var cols: Int
    var rows: Int
    /// Printable width/height per page.
    var tw: Double
    var th: Double
    /// Step between pages (printable size minus overlap).
    var sx: Double
    var sy: Double
    var overlap: Double
    /// Part of the image used for the whole poster.
    var base: Crop
}

func rowName(_ r: Int) -> String {
    r < 26 ? String(Character(UnicodeScalar(UInt8(65 + r)))) : "R\(r + 1)"
}

func buildPoster(_ o: PosterOptions) -> LayoutResult<PosterInfo> {
    let a = o.photo?.aspect ?? 4.0 / 3.0
    let m = o.margin
    let ov = max(0, o.overlap)
    let orients: [PageOrientation] = o.orientation == .auto ? [.portrait, .landscape] : [o.orientation]
    let fill = o.sizeBy == .grid && o.fill

    struct Candidate {
        var orient: PageOrientation
        var page: MMSize
        var tw, th, sx, sy, pw, ph: Double
        var cols, rows: Int
        var n: Int { cols * rows }
        var util: Double { pw * ph / (Double(n) * tw * th) }
        var shapeMatch: Double
    }

    var best: Candidate?
    for orient in orients {
        let page = orientPaper(o.paper, orient)
        let tw = page.w - 2 * m
        let th = page.h - 2 * m
        if tw - ov < 5 || th - ov < 5 { continue }
        let sx = tw - ov
        let sy = th - ov
        let pw: Double
        let ph: Double
        switch o.sizeBy {
        case .grid:
            let cols = max(1, o.cols)
            let rows = max(1, o.rows)
            let gw = Double(cols) * tw - Double(cols - 1) * ov
            let gh = Double(rows) * th - Double(rows - 1) * ov
            if fill {
                pw = gw
                ph = gh
            } else {
                pw = min(gw, gh * a)
                ph = pw / a
            }
        case .width:
            pw = o.width
            ph = pw / a
        case .height:
            ph = o.height
            pw = ph * a
        }
        if !(pw > 0 && ph > 0) { continue }
        let cols = max(1, Int(((pw - ov) / sx - 1e-6).rounded(.up)))
        let rows = max(1, Int(((ph - ov) / sy - 1e-6).rounded(.up)))
        let cand = Candidate(orient: orient, page: page, tw: tw, th: th, sx: sx, sy: sy, pw: pw, ph: ph,
                             cols: cols, rows: rows, shapeMatch: fitFraction(pw, ph, a))
        if let b = best {
            if posterBetter(cand.pw * cand.ph, cand.n, cand.util, cand.shapeMatch,
                            than: b.pw * b.ph, b.n, b.util, b.shapeMatch, sizeBy: o.sizeBy, fill: fill) { best = cand }
        } else {
            best = cand
        }
    }

    guard let b = best else { return LayoutResult(pages: [], info: nil, error: .margins) }
    if b.n > 150 { return LayoutResult(pages: [], info: nil, error: .tooMany(b.n)) }

    var base = Crop.full
    if let photo = o.photo, fill {
        base = computeCrop(imageAspect: a, targetAspect: b.pw / b.ph, adjust: photo.adjust)
    }
    var pages: [Page] = []
    for r in 0..<b.rows {
        for c in 0..<b.cols {
            let x0 = Double(c) * b.sx
            let y0 = Double(r) * b.sy
            let w = min(x0 + b.tw, b.pw) - x0
            let h = min(y0 + b.th, b.ph) - y0
            let cut = MMRect(x: m, y: m, w: w, h: h)
            var pg = Page(w: b.page.w, h: b.page.h, label: "\(rowName(r))\(c + 1)")
            if let photo = o.photo {
                let crop = Crop(x: base.x + base.w * x0 / b.pw, y: base.y + base.h * y0 / b.ph,
                                w: base.w * w / b.pw, h: base.h * h / b.ph)
                pg.items = [PlacedItem(photoID: photo.id, rect: cut, rot: 0, userRot: photo.rotation, crop: crop, cut: cut)]
            } else {
                pg.placeholders = [cut]
            }
            if o.guides { addPosterGuides(&pg, m: m, w: w, h: h, r: r, c: c, rows: b.rows, cols: b.cols, sx: b.sx, sy: b.sy, ov: ov) }
            pages.append(pg)
        }
    }
    let info = PosterInfo(orientation: b.orient, page: b.page, posterW: b.pw, posterH: b.ph, cols: b.cols, rows: b.rows,
                          tw: b.tw, th: b.th, sx: b.sx, sy: b.sy, overlap: ov, base: base)
    return LayoutResult(pages: pages, info: info, error: nil)
}

// swiftlint:disable:next function_parameter_count
private func posterBetter(_ area: Double, _ n: Int, _ util: Double, _ shape: Double,
                          than bArea: Double, _ bn: Int, _ bUtil: Double, _ bShape: Double,
                          sizeBy: PosterSizeBy, fill: Bool) -> Bool {
    let close = { (x: Double, y: Double) in abs(x - y) <= max(abs(x), abs(y)) * 1e-6 }
    if sizeBy == .grid {
        // Biggest poster wins, then the least cropping, then fewest pages.
        if !close(area, bArea) { return area > bArea }
        if fill && !close(shape, bShape) { return shape > bShape }
        return n < bn
    }
    // Fixed size: fewest pages, then least wasted paper.
    if n != bn { return n < bn }
    return util > bUtil * (1 + 1e-9)
}

// swiftlint:disable:next function_parameter_count
private func addPosterGuides(_ pg: inout Page, m: Double, w: Double, h: Double, r: Int, c: Int,
                             rows: Int, cols: Int, sx: Double, sy: Double, ov: Double) {
    guard m >= 2 else { return }
    let off = 1.0
    let len = min(5, m - 1.5)
    // Trim marks at the corners of the printed area.
    pg.under += cornerMarks(MMRect(x: m, y: m, w: w, h: h), off: off, len: len, gray: 0.2)

    // Where the next page's edge lines up when overlapping.
    if ov > 0 {
        let dash = [1.0, 0.8]
        if c < cols - 1 {
            let x = m + sx
            pg.under.append(.line(x1: x, y1: m - off, x2: x, y2: m - off - len, lineWidth: 0.2, gray: 0.35, dash: dash))
            pg.under.append(.line(x1: x, y1: m + h + off, x2: x, y2: m + h + off + len, lineWidth: 0.2, gray: 0.35, dash: dash))
        }
        if r < rows - 1 {
            let y = m + sy
            pg.under.append(.line(x1: m - off, y1: y, x2: m - off - len, y2: y, lineWidth: 0.2, gray: 0.35, dash: dash))
            pg.under.append(.line(x1: m + w + off, y1: y, x2: m + w + off + len, y2: y, lineWidth: 0.2, gray: 0.35, dash: dash))
        }
    }

    // Page label and a tiny map of where this page goes.
    guard m >= 4 else { return }
    let size = min(8, m * 0.55 / 0.3528)
    let cap = size * 0.3528 * 0.72
    let baseline = pg.h - m / 2 + cap / 2
    let label = pg.label ?? ""
    pg.over.append(.text(x: m, y: baseline, size: size,
                         text: "\(label)   (\(rows) down × \(cols) across, A1 is top-left)", gray: 0.35))
    let cell = min(2.6, (m - 1.6) / Double(rows), 40 / Double(cols))
    guard cell >= 0.7 else { return }
    let x0 = pg.w - m - Double(cols) * cell
    let y0 = pg.h - m / 2 - Double(rows) * cell / 2
    for rr in 0..<rows {
        for cc in 0..<cols {
            let here = rr == r && cc == c
            pg.over.append(.rect(MMRect(x: x0 + Double(cc) * cell, y: y0 + Double(rr) * cell, w: cell, h: cell),
                                 lineWidth: 0.12, gray: 0.55, fill: here ? 0.35 : nil))
        }
    }
}
