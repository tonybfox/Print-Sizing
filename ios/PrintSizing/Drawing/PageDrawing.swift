import UIKit

// Drawing laid-out pages into a Core Graphics context with the origin at the
// page's top-left and y pointing down (UIKit's convention). The same code
// draws the on-screen preview, printed pages and the PDF.

struct PageDrawer {
    /// Context units per millimetre.
    var scale: Double
    /// Thinnest line drawn, in context units (keeps hairlines visible on screen).
    var minLineWidth: Double = 0
    /// Shows empty slots; off for printing.
    var showPlaceholders = true
    /// The image (EXIF orientation applied) to draw for a placed photo.
    var image: (PlacedItem) -> CGImage?

    func draw(_ page: Page, in ctx: CGContext) {
        let k = scale
        ctx.saveGState()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: page.w * k, height: page.h * k))
        drawMarks(page.under, in: ctx)
        if showPlaceholders {
            for r in page.placeholders {
                let rect = cgRect(r)
                ctx.setFillColor(UIColor(red: 0xEE / 255, green: 0xF1 / 255, blue: 0xF6 / 255, alpha: 1).cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(UIColor(red: 0xB6 / 255, green: 0xBF / 255, blue: 0xCC / 255, alpha: 1).cgColor)
                ctx.setLineWidth(max(1, 0.3 * k))
                ctx.setLineDash(phase: 0, lengths: [2 * k, 1.5 * k])
                ctx.stroke(rect)
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        for it in page.items {
            guard let img = image(it) else { continue }
            drawPhoto(ctx, img, userRot: it.userRot, crop: it.crop, placeRot: it.rot, in: cgRect(it.rect))
        }
        drawMarks(page.over, in: ctx)
        ctx.restoreGState()
    }

    func cgRect(_ r: MMRect) -> CGRect {
        CGRect(x: r.x * scale, y: r.y * scale, width: r.w * scale, height: r.h * scale)
    }

    func drawMarks(_ marks: [Mark], in ctx: CGContext) {
        let k = scale
        for m in marks {
            ctx.saveGState()
            switch m {
            case let .line(x1, y1, x2, y2, lw, gray, dash):
                ctx.setStrokeColor(gray: gray, alpha: 1)
                ctx.setLineWidth(max(minLineWidth, lw * k))
                ctx.setLineDash(phase: 0, lengths: (dash ?? []).map { $0 * k })
                ctx.move(to: CGPoint(x: x1 * k, y: y1 * k))
                ctx.addLine(to: CGPoint(x: x2 * k, y: y2 * k))
                ctx.strokePath()
            case let .rect(r, lw, gray, fill):
                if let f = fill {
                    ctx.setFillColor(gray: f, alpha: 1)
                    ctx.fill(cgRect(r))
                }
                ctx.setStrokeColor(gray: gray, alpha: 1)
                ctx.setLineWidth(max(minLineWidth, lw * k))
                ctx.stroke(cgRect(r))
            case let .text(x, y, size, text, gray):
                let font = UIFont(name: "Helvetica", size: size / ptPerMM * k) ?? .systemFont(ofSize: size / ptPerMM * k)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: gray, alpha: 1)]
                UIGraphicsPushContext(ctx)
                (text as NSString).draw(at: CGPoint(x: x * k, y: y * k - font.ascender), withAttributes: attrs)
                UIGraphicsPopContext()
            }
            ctx.restoreGState()
        }
    }
}

/// Draw `crop` (in the photo's rotated space) of `img`, turned by the user's
/// rotation plus the placement's quarter turn, filling `dest`.
func drawPhoto(_ ctx: CGContext, _ img: CGImage, userRot: Int, crop: Crop, placeRot: Int, in dest: CGRect) {
    let s = sourceRect(crop, rotation: userRot)
    let iw = Double(img.width)
    let ih = Double(img.height)
    let x0 = clamp((s.x * iw).rounded(), 0, iw - 1)
    let y0 = clamp((s.y * ih).rounded(), 0, ih - 1)
    let x1 = clamp(((s.x + s.w) * iw).rounded(), x0 + 1, iw)
    let y1 = clamp(((s.y + s.h) * ih).rounded(), y0 + 1, ih)
    let full = x0 == 0 && y0 == 0 && x1 == iw && y1 == ih
    guard let cropped = full ? img : img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return }

    let r = ((userRot + placeRot) % 360 + 360) % 360
    let swap = r % 180 != 0
    let w = swap ? dest.height : dest.width
    let h = swap ? dest.width : dest.height
    ctx.saveGState()
    ctx.clip(to: dest)
    ctx.translateBy(x: dest.midX, y: dest.midY)
    ctx.rotate(by: CGFloat(r) * .pi / 180)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    ctx.restoreGState()
}

/// The whole poster as it will look assembled, with page seams, overlap
/// strips and page labels. `k` is context units per millimetre.
func drawPosterPreview(_ ctx: CGContext, plan: Plan, photo: Photo?, k: Double) {
    guard let i = plan.poster else { return }
    let gw = Double(i.cols - 1) * i.sx + i.tw
    let gh = Double(i.rows - 1) * i.sy + i.th
    ctx.saveGState()
    ctx.setFillColor(UIColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: gw * k, height: gh * k))
    // Hatch the paper that ends up unused beyond the image.
    ctx.setStrokeColor(UIColor(white: 0, alpha: 0.06).cgColor)
    ctx.setLineWidth(1)
    var d = -gh * k
    while d < gw * k {
        ctx.move(to: CGPoint(x: d, y: gh * k))
        ctx.addLine(to: CGPoint(x: d + gh * k, y: 0))
        d += 8
    }
    ctx.strokePath()

    let posterRect = CGRect(x: 0, y: 0, width: i.posterW * k, height: i.posterH * k)
    if let p = photo {
        drawPhoto(ctx, p.preview, userRot: p.rotation, crop: i.base, placeRot: 0, in: posterRect)
    } else {
        ctx.setFillColor(UIColor(red: 0xEE / 255, green: 0xF1 / 255, blue: 0xF6 / 255, alpha: 1).cgColor)
        ctx.fill(posterRect)
    }

    if i.overlap > 0 {
        ctx.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
        for c in 1..<max(1, i.cols) { ctx.fill(CGRect(x: Double(c) * i.sx * k, y: 0, width: i.overlap * k, height: gh * k)) }
        for r in 1..<max(1, i.rows) { ctx.fill(CGRect(x: 0, y: Double(r) * i.sy * k, width: gw * k, height: i.overlap * k)) }
    }
    ctx.setLineWidth(max(1, 0.35 * k))
    func seam(_ a: CGPoint, _ b: CGPoint) {
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(UIColor(white: 0, alpha: 0.55).cgColor)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.95).cgColor)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }
    for c in 1..<max(1, i.cols) { seam(CGPoint(x: Double(c) * i.sx * k, y: 0), CGPoint(x: Double(c) * i.sx * k, y: gh * k)) }
    for r in 1..<max(1, i.rows) { seam(CGPoint(x: 0, y: Double(r) * i.sy * k), CGPoint(x: gw * k, y: Double(r) * i.sy * k)) }
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
    ctx.setLineWidth(1)
    ctx.stroke(CGRect(x: 0.5, y: 0.5, width: gw * k - 1, height: gh * k - 1))

    // Page labels.
    let fs = max(10, min(16, min(i.sx, i.sy) * k * 0.12))
    let font = UIFont.systemFont(ofSize: fs, weight: .semibold)
    UIGraphicsPushContext(ctx)
    for (n, pg) in plan.pages.enumerated() {
        let label = (pg.label ?? "") as NSString
        let x = Double(n % i.cols) * i.sx * k + 4
        let y = Double(n / i.cols) * i.sy * k + 4
        let w = label.size(withAttributes: [.font: font]).width + 8
        UIColor(white: 0, alpha: 0.55).setFill()
        UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: fs + 6), cornerRadius: 4).fill()
        label.draw(at: CGPoint(x: x + 4, y: y + 3), withAttributes: [.font: font, .foregroundColor: UIColor.white])
    }
    UIGraphicsPopContext()
    ctx.restoreGState()
}

func posterGridSize(_ i: PosterInfo) -> CGSize {
    CGSize(width: Double(i.cols - 1) * i.sx + i.tw, height: Double(i.rows - 1) * i.sy + i.th)
}
