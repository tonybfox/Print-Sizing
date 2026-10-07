import Foundation

// Shared layout types. Everything is in millimetres with the origin at the
// top-left of the page. This folder is plain Swift (no UIKit) so it can be
// unit tested with `swift test`.

let mmPerInch = 25.4
let ptPerMM = 72.0 / 25.4

struct MMRect: Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct MMSize: Hashable {
    var w: Double
    var h: Double
}

enum PageOrientation: String, Codable, CaseIterable, Identifiable {
    case auto, portrait, landscape
    var id: String { rawValue }
}

func orientPaper(_ paper: MMSize, _ orientation: PageOrientation) -> MMSize {
    let s = min(paper.w, paper.h)
    let l = max(paper.w, paper.h)
    return orientation == .landscape ? MMSize(w: l, h: s) : MMSize(w: s, h: l)
}

/// Guide marks drawn under or over the photos.
enum Mark: Hashable {
    case line(x1: Double, y1: Double, x2: Double, y2: Double, lineWidth: Double, gray: Double, dash: [Double]?)
    case rect(MMRect, lineWidth: Double, gray: Double, fill: Double?)
    /// Left-aligned text; y is the baseline. size in points.
    case text(x: Double, y: Double, size: Double, text: String, gray: Double)
}

/// A photo placed on a page.
struct PlacedItem: Hashable {
    var photoID: Int
    var rect: MMRect
    /// Extra quarter turn (0 or 90) applied so the photo suits its slot.
    var rot: Int
    /// The photo's own rotation chosen by the user (0, 90, 180, 270).
    var userRot: Int
    /// Part of the photo shown, in the photo's rotated ("oriented") space.
    var crop: Crop
    /// Outline to cut along.
    var cut: MMRect
}

struct Page: Hashable {
    var w: Double
    var h: Double
    var items: [PlacedItem] = []
    var placeholders: [MMRect] = []
    var under: [Mark] = []
    var over: [Mark] = []
    var label: String?

    var isLandscape: Bool { w > h }
}

/// What the layout needs to know about a photo.
struct PhotoRef: Hashable {
    var id: Int
    /// Width / height after the user's rotation.
    var aspect: Double
    var copies: Int = 1
    var rotation: Int = 0
    var adjust = CropAdjust()
}

enum LayoutError: Hashable {
    case margins
    case tooBig(cw: Double, ch: Double)
    case tooMany(Int)
}

struct LayoutResult<Info> {
    var pages: [Page]
    var info: Info?
    var error: LayoutError?
}
