import XCTest
@testable import PrintLayout

// Mirrors tests/layout.test.mjs for the web version.
final class LayoutTests: XCTestCase {
    let a4 = MMSize(w: 210, h: 297)
    let p4x6 = MMSize(w: 101.6, h: 152.4)

    func photo(_ aspect: Double, id: Int = 1, copies: Int = 1) -> PhotoRef {
        PhotoRef(id: id, aspect: aspect, copies: copies)
    }

    func sheet(_ edit: (inout SheetOptions) -> Void) -> LayoutResult<SheetInfo> {
        var o = SheetOptions(paper: a4)
        edit(&o)
        return buildSheet(o)
    }

    func testFitCount() {
        XCTAssertEqual(fitCount(100, 50, 0), 2)
        XCTAssertEqual(fitCount(100, 50, 1), 1)
        XCTAssertEqual(fitCount(101, 50, 1), 2)
        XCTAssertEqual(fitCount(40, 50, 0), 0)
    }

    func testSixLandscapeOnA4() {
        let r = sheet { $0.photos = [photo(1.5)]; $0.perPage = 6 }
        XCTAssertEqual(r.info?.orientation, .portrait)
        XCTAssertEqual(r.info?.cols, 2)
        XCTAssertEqual(r.info?.rows, 3)
    }

    func testPagesKeepOrder() {
        let r = sheet { o in o.photos = (1...7).map { photo(1.5, id: $0) }; o.perPage = 6 }
        XCTAssertEqual(r.pages.count, 2)
        XCTAssertEqual(r.pages[0].items.count, 6)
        XCTAssertEqual(r.pages[1].items.first?.photoID, 7)
    }

    func testCopiesAndFillPage() {
        XCTAssertEqual(sheet { $0.photos = [photo(1.5, copies: 2)]; $0.perPage = 4 }.pages[0].items.count, 2)
        let f = sheet { $0.photos = [photo(1.5)]; $0.perPage = 4; $0.fillPage = true }
        XCTAssertEqual(f.pages.count, 1)
        XCTAssertEqual(f.pages[0].items.count, 4)
    }

    func testFitKeepsAspectInsidePage() {
        let r = sheet { $0.photos = [photo(1.5, id: 1), photo(0.75, id: 2)]; $0.perPage = 2 }
        for it in r.pages[0].items {
            let a = it.photoID == 1 ? 1.5 : 0.75
            XCTAssertEqual(it.rect.w / it.rect.h, it.rot != 0 ? 1 / a : a, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(it.rect.x, 5 - 1e-9)
            XCTAssertLessThanOrEqual(it.rect.x + it.rect.w, 205 + 1e-9)
            XCTAssertLessThanOrEqual(it.rect.y + it.rect.h, 292 + 1e-9)
        }
    }

    func testFillCropsToSlotShape() {
        let it = sheet { $0.photos = [photo(1.5)]; $0.perPage = 4; $0.fill = true }.pages[0].items[0]
        let target = it.rot != 0 ? it.rect.h / it.rect.w : it.rect.w / it.rect.h
        XCTAssertEqual(it.crop.w / it.crop.h * 1.5, target, accuracy: 1e-9)
    }

    func testExactTwoByThreeOnA4() {
        let items = sheet { $0.sizing = .exact; $0.fill = true; $0.photos = [photo(2.0 / 3.0)]; $0.fillPage = true }.pages[0].items
        XCTAssertGreaterThanOrEqual(items.count, 10)
        for it in items {
            let dims = [it.rect.w, it.rect.h].sorted()
            XCTAssertEqual(dims[0], 50.8, accuracy: 1e-6)
            XCTAssertEqual(dims[1], 76.2, accuracy: 1e-6)
            XCTAssertGreaterThanOrEqual(it.rect.x, 5 - 1e-9)
            XCTAssertLessThanOrEqual(it.rect.x + it.rect.w, 205 + 1e-9)
            XCTAssertLessThanOrEqual(it.rect.y + it.rect.h, 292 + 1e-9)
        }
        for i in items.indices {
            for j in items.indices where j > i {
                let a = items[i].rect, b = items[j].rect
                let sepX = max(b.x - (a.x + a.w), a.x - (b.x + b.w))
                let sepY = max(b.y - (a.y + a.h), a.y - (b.y + b.h))
                XCTAssertGreaterThanOrEqual(max(sepX, sepY), 3 - 1e-6, "pieces \(i) and \(j) too close")
            }
        }
    }

    func testExactRotatesPhotoInTurnedSlot() {
        let r = sheet { $0.sizing = .exact; $0.fill = true; $0.photos = [photo(0.75)]; $0.fillPage = true }
        for it in r.pages[0].items {
            XCTAssertEqual(it.rot, it.rect.w > it.rect.h ? 90 : 0)
            XCTAssertEqual(it.crop.w / it.crop.h * 0.75, 2.0 / 3.0, accuracy: 1e-9)
        }
    }

    func testMatchOrientation() {
        let on = sheet { $0.sizing = .exact; $0.fill = true; $0.photos = [photo(1.5)] }.pages[0].items[0]
        XCTAssertEqual(on.crop.w / on.crop.h * 1.5, 1.5, accuracy: 1e-9)
        let off = sheet { $0.sizing = .exact; $0.fill = true; $0.matchOrientation = false; $0.photos = [photo(1.5)] }.pages[0].items[0]
        XCTAssertEqual(off.crop.w / off.crop.h * 1.5, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testTooBig() {
        let r = sheet { $0.sizing = .exact; $0.pieceW = 300; $0.pieceH = 400; $0.photos = [photo(1)] }
        if case .tooBig = r.error {} else { XCTFail("expected tooBig, got \(String(describing: r.error))") }
    }

    func testPackingMixesOrientations() {
        let pure = max(fitCount(200, 50.8, 3) * fitCount(287, 76.2, 3), fitCount(200, 76.2, 3) * fitCount(287, 50.8, 3))
        let mixed = packPieces(200, 287, 50.8, 76.2, 3)
        XCTAssertGreaterThanOrEqual(mixed.count, pure)
        XCTAssertEqual(mixed.slots.count, mixed.count)
    }

    func testOnePhotoBorderless6x4() {
        var o = SheetOptions(paper: p4x6)
        o.margin = 0
        o.gap = 0
        o.perPage = 1
        o.fill = true
        o.photos = [photo(1.5)]
        let r = buildSheet(o)
        XCTAssertEqual(r.info?.orientation, .landscape)
        XCTAssertEqual(r.pages[0].items[0].rect.w, 152.4, accuracy: 1e-6)
        XCTAssertEqual(r.pages[0].items[0].rect.h, 101.6, accuracy: 1e-6)
    }

    func testPosterGrid() throws {
        var o = PosterOptions(paper: a4)
        o.photo = photo(0.75)
        let r = buildPoster(o)
        let info = try XCTUnwrap(r.info)
        XCTAssertEqual(r.pages.count, info.cols * info.rows)
        XCTAssertEqual(info.posterW / info.posterH, 0.75, accuracy: 1e-9)
        let area = r.pages.reduce(0.0) { $0 + $1.items[0].crop.w * $1.items[0].crop.h }
        XCTAssertEqual(area, 1, accuracy: 1e-9)
    }

    func testPosterWidthWithOverlap() throws {
        var o = PosterOptions(paper: a4)
        o.orientation = .portrait
        o.overlap = 10
        o.sizeBy = .width
        o.width = 600
        o.photo = photo(1)
        let r = buildPoster(o)
        let info = try XCTUnwrap(r.info)
        XCTAssertEqual(info.posterW, 600, accuracy: 1e-6)
        XCTAssertEqual(info.cols, Int((590 / info.sx).rounded(.up)))
        let a = r.pages[0].items[0].crop, b = r.pages[1].items[0].crop
        XCTAssertEqual((a.x + a.w - b.x) * info.posterW, 10, accuracy: 1e-6)
    }

    func testPosterFill() throws {
        var o = PosterOptions(paper: a4)
        o.orientation = .portrait
        o.cols = 3
        o.rows = 3
        o.fill = true
        o.guides = false
        o.photo = photo(1.5)
        let info = try XCTUnwrap(buildPoster(o).info)
        XCTAssertEqual(info.posterW, 3 * 198, accuracy: 1e-6)
        XCTAssertEqual(info.posterH, 3 * 285, accuracy: 1e-6)
        XCTAssertEqual(info.base.w / info.base.h * 1.5, info.posterW / info.posterH, accuracy: 1e-9)
    }

    func testComputeCrop() {
        let c = computeCrop(imageAspect: 2, targetAspect: 1)
        XCTAssertEqual(c.w, 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.x, 0.25, accuracy: 1e-9)
        let edge = computeCrop(imageAspect: 2, targetAspect: 1, adjust: CropAdjust(cx: 0.99, cy: 0.5, zoom: 1))
        XCTAssertEqual(edge.x, 0.5, accuracy: 1e-9)
    }

    func testSourceRectRotations() {
        func rotate(_ x: Double, _ y: Double, _ rot: Int) -> (Double, Double) {
            switch rot {
            case 90: return (1 - y, x)
            case 180: return (1 - x, 1 - y)
            case 270: return (y, 1 - x)
            default: return (x, y)
            }
        }
        for rot in [0, 90, 180, 270] {
            let (u, v) = rotate(0.2, 0.3, rot)
            let t = 1e-4
            let s = sourceRect(Crop(x: u - t / 2, y: v - t / 2, w: t, h: t), rotation: rot)
            XCTAssertEqual(s.x + s.w / 2, 0.2, accuracy: 1e-9)
            XCTAssertEqual(s.y + s.h / 2, 0.3, accuracy: 1e-9)
        }
    }

    func testRequiredLongSide() {
        // 2 x 3 in at 300 dpi from a 4000 x 3000 image, whole image shown, turned 90.
        let item = PlacedItem(photoID: 1, rect: MMRect(x: 0, y: 0, w: 50.8, h: 76.2), rot: 90, userRot: 0,
                              crop: .full, cut: MMRect(x: 0, y: 0, w: 50.8, h: 76.2))
        XCTAssertEqual(requiredLongSide(item: item, imageWidth: 4000, imageHeight: 3000, dpi: 300), 900, accuracy: 1)
        // Never more than the original.
        var big = item
        big.rect = MMRect(x: 0, y: 0, w: 1000, h: 1500)
        XCTAssertEqual(requiredLongSide(item: big, imageWidth: 4000, imageHeight: 3000, dpi: 300), 4000)
    }
}
