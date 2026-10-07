import Foundation

// Photo sheets: N photos per page as large as possible, or every photo at an
// exact size packed as tightly as possible. Port of js/layout.js (buildSheet).

private let EPS = 1e-6

enum Sizing: String, Codable, CaseIterable {
    case count, exact
}

enum CutGuides: String, Codable, CaseIterable, Identifiable {
    case none, outline, marks
    var id: String { rawValue }
}

struct SheetOptions {
    var paper: MMSize
    var orientation: PageOrientation = .auto
    var margin: Double = 5
    var gap: Double = 3
    var sizing: Sizing = .count
    var perPage: Int = 6
    var pieceW: Double = 50.8
    var pieceH: Double = 76.2
    /// true: fill each slot and crop; false: show the whole photo.
    var fill: Bool = false
    var autoRotate: Bool = true
    var matchOrientation: Bool = true
    var guides: CutGuides = .none
    var fillPage: Bool = false
    var photos: [PhotoRef] = []
}

struct SheetInfo: Hashable {
    var orientation: PageOrientation
    var page: MMSize
    var perPage: Int
    var cols: Int?
    var rows: Int?
    var slotW: Double
    var slotH: Double
    var photoCount: Int
}

/// How many pieces of `piece` fit along `len` with `gap` between them.
func fitCount(_ len: Double, _ piece: Double, _ gap: Double) -> Int {
    guard piece > 0, piece <= len + EPS else { return 0 }
    return Int(((len + gap + EPS) / (piece + gap)).rounded(.down))
}

/// Fraction of a cell a photo of `aspect` covers when fitted inside it.
func fitFraction(_ cellW: Double, _ cellH: Double, _ aspect: Double) -> Double {
    let ca = cellW / cellH
    return min(ca / aspect, aspect / ca)
}

struct Grid: Hashable {
    var cols: Int
    var rows: Int
    var cellW: Double
    var cellH: Double
    var score: Double
    var empty: Int
    var turned: Int
}

/// Columns × rows for `n` photos that shows them as large as possible.
func bestGrid(_ cw: Double, _ ch: Double, _ n: Int, _ gap: Double, _ aspects: [Double], _ autoRotate: Bool) -> Grid? {
    guard n >= 1, !aspects.isEmpty else { return nil }
    var best: Grid?
    for cols in 1...n {
        let rows = (n + cols - 1) / cols
        let cellW = (cw - Double(cols - 1) * gap) / Double(cols)
        let cellH = (ch - Double(rows - 1) * gap) / Double(rows)
        if cellW <= EPS || cellH <= EPS { continue }
        var score = 0.0
        var turned = 0
        for a in aspects {
            let f0 = fitFraction(cellW, cellH, a)
            let f1 = autoRotate ? fitFraction(cellW, cellH, 1 / a) : 0
            if f1 > f0 * (1 + 1e-9) { turned += 1 }
            score += max(f0, f1) * cellW * cellH
        }
        score /= Double(aspects.count)
        let cand = Grid(cols: cols, rows: rows, cellW: cellW, cellH: cellH, score: score, empty: cols * rows - n, turned: turned)
        guard let b = best else {
            best = cand
            continue
        }
        let better = score > b.score * (1 + 1e-9)
        let tie = score >= b.score * (1 - 1e-9)
        if better || (tie && (cand.empty < b.empty || (cand.empty == b.empty && turned < b.turned))) { best = cand }
    }
    return best
}

/// Slot rectangles for a grid; a short last row is centred.
func gridSlots(_ g: Grid, _ n: Int, _ gap: Double, _ ox: Double, _ oy: Double, _ cw: Double) -> [MMRect] {
    (0..<n).map { i in
        let r = i / g.cols
        let c = i % g.cols
        let inRow = min(g.cols, n - r * g.cols)
        let rowW = Double(inRow) * g.cellW + Double(inRow - 1) * gap
        let x0 = ox + (cw - rowW) / 2
        return MMRect(x: x0 + Double(c) * (g.cellW + gap), y: oy + Double(r) * (g.cellH + gap), w: g.cellW, h: g.cellH)
    }
}

private struct PackBlock {
    var w: Double
    var h: Double
    var cols: Int
    var rows: Int
    var n: Int { cols * rows }
}

private struct Packing {
    var count: Int
    var horizontal: Bool
    var blocks: [PackBlock]
    var used: Int { blocks.filter { $0.n > 0 }.count }
}

/// Fit as many a × b pieces as possible into cw × ch. Tries both piece
/// orientations, plus a main block in one orientation with the leftover band
/// filled by turned pieces (still cuttable with straight cuts). Slots are
/// relative to the content area and centred.
func packPieces(_ cw: Double, _ ch: Double, _ a: Double, _ b: Double, _ gap: Double) -> (count: Int, slots: [MMRect]) {
    guard a > 0, b > 0 else { return (0, []) }
    let square = abs(a - b) < EPS
    let orients: [(Double, Double)] = square ? [(a, b)] : [(a, b), (b, a)]
    var best: Packing?
    func consider(_ p: Packing) {
        guard let cur = best else {
            best = p
            return
        }
        if p.count > cur.count || (p.count == cur.count && p.used < cur.used) { best = p }
    }
    for (pw, ph) in orients {
        let (qw, qh) = (ph, pw)
        // Rows of pw × ph across the top, leftover band below with turned pieces.
        let c1 = fitCount(cw, pw, gap)
        let r1max = fitCount(ch, ph, gap)
        for r1 in stride(from: c1 > 0 ? r1max : 0, through: 0, by: -1) {
            let usedH = Double(r1) * (ph + gap)
            let c2 = square ? 0 : fitCount(cw, qw, gap)
            let r2 = c2 > 0 ? fitCount(ch - usedH, qh, gap) : 0
            consider(Packing(count: c1 * r1 + c2 * r2, horizontal: true, blocks: [
                PackBlock(w: pw, h: ph, cols: c1, rows: r1),
                PackBlock(w: qw, h: qh, cols: c2, rows: r2),
            ]))
        }
        // Columns of pw × ph down the left, leftover band on the right.
        let r1b = fitCount(ch, ph, gap)
        let c1max = fitCount(cw, pw, gap)
        for c1 in stride(from: r1b > 0 ? c1max : 0, through: 0, by: -1) {
            let usedW = Double(c1) * (pw + gap)
            let r2 = square ? 0 : fitCount(ch, qh, gap)
            let c2 = r2 > 0 ? fitCount(cw - usedW, qw, gap) : 0
            consider(Packing(count: r1b * c1 + c2 * r2, horizontal: false, blocks: [
                PackBlock(w: pw, h: ph, cols: c1, rows: r1b),
                PackBlock(w: qw, h: qh, cols: c2, rows: r2),
            ]))
        }
    }
    guard let p = best, p.count > 0 else { return (0, []) }
    return (p.count, packedSlots(p, cw, ch, gap))
}

private func packedSlots(_ p: Packing, _ cw: Double, _ ch: Double, _ gap: Double) -> [MMRect] {
    let blocks = p.blocks.filter { $0.n > 0 }
    let widths = blocks.map { Double($0.cols) * $0.w + Double($0.cols - 1) * gap }
    let heights = blocks.map { Double($0.rows) * $0.h + Double($0.rows - 1) * gap }
    var slots: [MMRect] = []
    if p.horizontal {
        let total = heights.reduce(0, +) + gap * Double(blocks.count - 1)
        var y = (ch - total) / 2
        for (i, b) in blocks.enumerated() {
            let x0 = (cw - widths[i]) / 2
            for r in 0..<b.rows {
                for c in 0..<b.cols {
                    slots.append(MMRect(x: x0 + Double(c) * (b.w + gap), y: y + Double(r) * (b.h + gap), w: b.w, h: b.h))
                }
            }
            y += heights[i] + gap
        }
    } else {
        let total = widths.reduce(0, +) + gap * Double(blocks.count - 1)
        var x = (cw - total) / 2
        for (i, b) in blocks.enumerated() {
            let y0 = (ch - heights[i]) / 2
            for r in 0..<b.rows {
                for c in 0..<b.cols {
                    slots.append(MMRect(x: x + Double(c) * (b.w + gap), y: y0 + Double(r) * (b.h + gap), w: b.w, h: b.h))
                }
            }
            x += widths[i] + gap
        }
    }
    return slots
}

func buildSheet(_ o: SheetOptions) -> LayoutResult<SheetInfo> {
    let photos = o.photos
    let exact = o.sizing == .exact
    let perPage = max(1, o.perPage)
    let aspects = photos.isEmpty ? [1.5] : photos.map(\.aspect)
    let orients: [PageOrientation] = o.orientation == .auto ? [.portrait, .landscape] : [o.orientation]

    struct Candidate {
        var orient: PageOrientation
        var page: MMSize
        var score: Double
        var turned: Int
        var grid: Grid?
        var slots: [MMRect]
    }

    var best: Candidate?
    var content: (cw: Double, ch: Double)?
    for orient in orients {
        let page = orientPaper(o.paper, orient)
        let cw = page.w - 2 * o.margin
        let ch = page.h - 2 * o.margin
        if cw <= EPS || ch <= EPS { continue }
        if content == nil { content = (cw, ch) }
        let cand: Candidate
        if exact {
            let pk = packPieces(cw, ch, o.pieceW, o.pieceH, o.gap)
            if pk.count == 0 { continue }
            let slots = pk.slots.map { MMRect(x: $0.x + o.margin, y: $0.y + o.margin, w: $0.w, h: $0.h) }
            cand = Candidate(orient: orient, page: page, score: Double(pk.count), turned: 0, grid: nil, slots: slots)
        } else {
            guard let g = bestGrid(cw, ch, perPage, o.gap, aspects, o.autoRotate) else { continue }
            cand = Candidate(orient: orient, page: page, score: g.score, turned: g.turned, grid: g,
                             slots: gridSlots(g, perPage, o.gap, o.margin, o.margin, cw))
        }
        if let b = best {
            // On a tie prefer the page orientation that needs fewer photos turned.
            let tie = cand.score >= b.score * (1 - 1e-9) && cand.score <= b.score * (1 + 1e-9)
            if (!tie && cand.score > b.score) || (tie && cand.turned < b.turned) { best = cand }
        } else {
            best = cand
        }
    }

    guard let b = best else {
        guard let c = content else { return LayoutResult(pages: [], info: nil, error: .margins) }
        return LayoutResult(pages: [], info: nil, error: .tooBig(cw: c.cw, ch: c.ch))
    }

    let n = b.slots.count
    var entries: [PhotoRef] = []
    for p in photos { for _ in 0..<max(1, p.copies) { entries.append(p) } }
    if o.fillPage && !entries.isEmpty && entries.count % n != 0 {
        let base = entries
        var i = 0
        while entries.count % n != 0 {
            entries.append(base[i % base.count])
            i += 1
        }
    }

    var pages: [Page] = []
    if entries.isEmpty { pages.append(sheetPage(b.page, items: [], placeholders: b.slots, o)) }
    var start = 0
    while start < entries.count {
        let chunk = entries[start..<min(start + n, entries.count)]
        let items = chunk.enumerated().map { k, p in placeInSlot(p, b.slots[k], o, exact: exact) }
        pages.append(sheetPage(b.page, items: items, placeholders: [], o))
        start += n
    }

    let s0 = b.slots[0]
    let info = SheetInfo(orientation: b.orient, page: b.page, perPage: n, cols: b.grid?.cols, rows: b.grid?.rows,
                         slotW: s0.w, slotH: s0.h, photoCount: entries.count)
    return LayoutResult(pages: pages, info: info, error: nil)
}

func placeInSlot(_ photo: PhotoRef, _ slot: MMRect, _ o: SheetOptions, exact: Bool) -> PlacedItem {
    var rot = 0
    if exact {
        var pw = o.pieceW
        var ph = o.pieceH
        if o.matchOrientation && abs(pw - ph) > EPS && abs(photo.aspect - 1) > 0.01 {
            let l = max(pw, ph)
            let s = min(pw, ph)
            (pw, ph) = photo.aspect > 1 ? (l, s) : (s, l)
        }
        // The packer may have laid this slot sideways; turn the photo with it.
        if abs(pw - slot.w) > EPS { rot = 90 }
    } else if o.autoRotate {
        let f0 = fitFraction(slot.w, slot.h, photo.aspect)
        let f1 = fitFraction(slot.w, slot.h, 1 / photo.aspect)
        if f1 > f0 * (1 + 1e-9) { rot = 90 }
    }

    if o.fill {
        let target = rot != 0 ? slot.h / slot.w : slot.w / slot.h
        let crop = computeCrop(imageAspect: photo.aspect, targetAspect: target, adjust: photo.adjust)
        return PlacedItem(photoID: photo.id, rect: slot, rot: rot, userRot: photo.rotation, crop: crop, cut: slot)
    }
    let shown = rot != 0 ? 1 / photo.aspect : photo.aspect
    let w = min(slot.w, slot.h * shown)
    let h = w / shown
    let r = MMRect(x: slot.x + (slot.w - w) / 2, y: slot.y + (slot.h - h) / 2, w: w, h: h)
    return PlacedItem(photoID: photo.id, rect: r, rot: rot, userRot: photo.rotation, crop: .full, cut: exact ? slot : r)
}

private func sheetPage(_ page: MMSize, items: [PlacedItem], placeholders: [MMRect], _ o: SheetOptions) -> Page {
    var p = Page(w: page.w, h: page.h, items: items, placeholders: placeholders)
    switch o.guides {
    case .outline:
        p.over = items.map { .rect($0.cut, lineWidth: 0.2, gray: 0.6, fill: nil) }
    case .marks:
        p.under = items.flatMap { cornerMarks($0.cut, off: 1, len: 4, gray: 0.25) }
    case .none:
        break
    }
    return p
}

/// Short crop marks pointing outwards from each corner of r.
func cornerMarks(_ r: MMRect, off: Double, len: Double, gray: Double, lineWidth: Double = 0.15) -> [Mark] {
    var out: [Mark] = []
    for (x, sx) in [(r.x, -1.0), (r.x + r.w, 1.0)] {
        for (y, sy) in [(r.y, -1.0), (r.y + r.h, 1.0)] {
            out.append(.line(x1: x + sx * off, y1: y, x2: x + sx * (off + len), y2: y, lineWidth: lineWidth, gray: gray, dash: nil))
            out.append(.line(x1: x, y1: y + sy * off, x2: x, y2: y + sy * (off + len), lineWidth: lineWidth, gray: gray, dash: nil))
        }
    }
    return out
}
