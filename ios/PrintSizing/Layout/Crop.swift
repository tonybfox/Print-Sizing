import Foundation

/// Normalised rectangle (0...1) of an image.
struct Crop: Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    static let full = Crop(x: 0, y: 0, w: 1, h: 1)
}

/// User's choice of what part of a photo to keep when it is cropped.
struct CropAdjust: Hashable, Codable {
    var cx = 0.5
    var cy = 0.5
    var zoom = 1.0
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(hi, max(lo, v)) }

func orientedAspect(width: Double, height: Double, rotation: Int) -> Double {
    rotation % 180 != 0 ? height / width : width / height
}

/// The largest window of `targetAspect` inside an image of `imageAspect`,
/// shrunk by the zoom and centred on (cx, cy) where possible.
func computeCrop(imageAspect: Double, targetAspect: Double, adjust: CropAdjust = CropAdjust()) -> Crop {
    var w = 1.0
    var h = 1.0
    if imageAspect > targetAspect { w = targetAspect / imageAspect } else { h = imageAspect / targetAspect }
    let z = max(1, adjust.zoom)
    w /= z
    h /= z
    return Crop(x: clamp(adjust.cx - w / 2, 0, 1 - w), y: clamp(adjust.cy - h / 2, 0, 1 - h), w: w, h: h)
}

/// Keep the crop centre where the crop window can actually reach.
func clampAdjust(_ a: CropAdjust, imageAspect: Double, targetAspect: Double) -> CropAdjust {
    var out = a
    out.zoom = clamp(a.zoom, 1, 6)
    let c = computeCrop(imageAspect: imageAspect, targetAspect: targetAspect, adjust: out)
    out.cx = clamp(a.cx, c.w / 2, 1 - c.w / 2)
    out.cy = clamp(a.cy, c.h / 2, 1 - c.h / 2)
    return out
}

/// Map a crop in oriented space back onto the original (unrotated) image.
/// `rotation` is the clockwise turn the user applied.
func sourceRect(_ c: Crop, rotation: Int) -> Crop {
    switch ((rotation % 360) + 360) % 360 {
    case 90: return Crop(x: c.y, y: 1 - c.x - c.w, w: c.h, h: c.w)
    case 180: return Crop(x: 1 - c.x - c.w, y: 1 - c.y - c.h, w: c.w, h: c.h)
    case 270: return Crop(x: 1 - c.y - c.h, y: c.x, w: c.h, h: c.w)
    default: return c
    }
}

/// Long side, in pixels, to decode an image at so `item` prints at `dpi`.
/// Never more than the image's own long side.
func requiredLongSide(item: PlacedItem, imageWidth: Double, imageHeight: Double, dpi: Double) -> Double {
    let turned = item.rot % 180 != 0
    let destW = (turned ? item.rect.h : item.rect.w) / mmPerInch * dpi
    let destH = (turned ? item.rect.w : item.rect.h) / mmPerInch * dpi
    let needW = destW / max(item.crop.w, 1e-6)
    let needH = destH / max(item.crop.h, 1e-6)
    let swap = item.userRot % 180 != 0
    let ow = swap ? imageHeight : imageWidth
    let oh = swap ? imageWidth : imageHeight
    let long = max(imageWidth, imageHeight)
    return min(long, (long * max(needW / ow, needH / oh)).rounded(.up))
}
