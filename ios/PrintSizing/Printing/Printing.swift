import UIKit

/// Photos decoded at print resolution, once per photo for a print job.
final class PrintImages {
    private let photos: [Int: Photo]
    private var need: [Int: Double] = [:]
    private var cache: [Int: CGImage] = [:]
    private let lock = NSLock()

    init(pages: [Page], photos: [Photo], dpi: Double) {
        self.photos = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for page in pages {
            for it in page.items {
                guard let p = self.photos[it.photoID] else { continue }
                let long = requiredLongSide(item: it, imageWidth: p.pixelWidth, imageHeight: p.pixelHeight, dpi: dpi)
                need[it.photoID] = max(need[it.photoID] ?? 0, long)
            }
        }
    }

    func image(for item: PlacedItem) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let img = cache[item.photoID] { return img }
        guard let p = photos[item.photoID] else { return nil }
        let img = p.decode(longSide: need[item.photoID] ?? Double(Photo.previewMax)) ?? p.preview
        cache[item.photoID] = img
        return img
    }

    /// Decode everything up front so drawing pages doesn't stall.
    func prepare(progress: (Int, Int) -> Void = { _, _ in }) {
        let ids = need.keys.sorted()
        for (n, id) in ids.enumerated() {
            progress(n, ids.count)
            _ = image(for: PlacedItem(photoID: id, rect: MMRect(x: 0, y: 0, w: 0, h: 0), rot: 0, userRot: 0, crop: .full,
                                      cut: MMRect(x: 0, y: 0, w: 0, h: 0)))
        }
    }
}

/// Draw `page` at actual size (72 pt per inch) on `paper`, turning it a
/// quarter if the paper is the other way round, and centring it if the paper
/// is slightly different (e.g. 10 × 15 cm loaded for a 6 × 4 in layout).
func drawOnPaper(_ page: Page, paper: CGRect, in ctx: CGContext, images: PrintImages) {
    let pw = page.w * ptPerMM
    let ph = page.h * ptPerMM
    var vw = paper.width
    var vh = paper.height
    ctx.saveGState()
    ctx.translateBy(x: paper.minX, y: paper.minY)
    let paperLandscape = paper.width > paper.height + 0.5
    let paperPortrait = paper.height > paper.width + 0.5
    if (page.w > page.h && paperPortrait) || (page.h > page.w && paperLandscape) {
        ctx.translateBy(x: paper.width, y: 0)
        ctx.rotate(by: .pi / 2)
        swap(&vw, &vh)
    }
    ctx.translateBy(x: (vw - pw) / 2, y: (vh - ph) / 2)
    PageDrawer(scale: ptPerMM, showPlaceholders: false, image: images.image(for:)).draw(page, in: ctx)
    ctx.restoreGState()
}

final class PageRenderer: UIPrintPageRenderer {
    let pages: [Page]
    let images: PrintImages

    init(pages: [Page], images: PrintImages) {
        self.pages = pages
        self.images = images
    }

    override var numberOfPages: Int { pages.count }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        guard pages.indices.contains(pageIndex), let ctx = UIGraphicsGetCurrentContext() else { return }
        drawOnPaper(pages[pageIndex], paper: paperRect, in: ctx, images: images)
    }
}

/// Runs the system print screen with the right paper already chosen.
final class PrintJob: NSObject, UIPrintInteractionControllerDelegate {
    let pages: [Page]
    let margin: Double
    let renderer: PageRenderer

    init(pages: [Page], margin: Double, images: PrintImages) {
        self.pages = pages
        self.margin = margin
        renderer = PageRenderer(pages: pages, images: images)
    }

    @MainActor
    func present(jobName: String, photoPaper: Bool, completion: @escaping (Error?) -> Void) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = photoPaper ? .photo : .general
        info.orientation = (pages.first?.isLandscape ?? false) ? .landscape : .portrait
        info.duplex = .none
        info.jobName = jobName

        let pic = UIPrintInteractionController.shared
        pic.printInfo = info
        pic.printPageRenderer = renderer
        pic.showsNumberOfCopies = true
        pic.showsPaperSelectionForLoadedPapers = true
        pic.delegate = self
        // The controller holds its delegate weakly; keep this job alive until it closes.
        PrintJob.current = self
        pic.present(animated: true) { _, _, error in
            PrintJob.current = nil
            completion(error)
        }
    }

    private static var current: PrintJob?

    func printInteractionController(_ printInteractionController: UIPrintInteractionController,
                                    choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        let size = pages.first.map { CGSize(width: $0.w * ptPerMM, height: $0.h * ptPerMM) } ?? CGSize(width: 595, height: 842)
        let near = { (a: CGFloat, b: CGFloat) in abs(a - b) <= 4 }
        let matches = paperList.filter { p in
            let s = p.paperSize
            return (near(s.width, size.width) && near(s.height, size.height)) || (near(s.width, size.height) && near(s.height, size.width))
        }
        // Epson borderless enlarges the image slightly, which would break exact sizes:
        // only use a borderless paper when the layout has no margin.
        let isBorderless = { (p: UIPrintPaper) in
            p.printableRect.width >= p.paperSize.width - 0.5 && p.printableRect.height >= p.paperSize.height - 0.5
        }
        let wantBorderless = margin <= 0
        if let m = matches.first(where: { isBorderless($0) == wantBorderless }) ?? matches.first { return m }
        return UIPrintPaper.bestPaper(forPageSize: size, withPapersFrom: paperList)
    }
}

/// A PDF of the pages at actual size, for saving to Files or a printer app.
func makePDF(pages: [Page], images: PrintImages, title: String) -> Data {
    let first = pages.first.map { CGRect(x: 0, y: 0, width: $0.w * ptPerMM, height: $0.h * ptPerMM) } ?? .zero
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Print Sizing"]
    return UIGraphicsPDFRenderer(bounds: first, format: format).pdfData { ctx in
        for page in pages {
            let bounds = CGRect(x: 0, y: 0, width: page.w * ptPerMM, height: page.h * ptPerMM)
            ctx.beginPage(withBounds: bounds, pageInfo: [:])
            drawOnPaper(page, paper: bounds, in: ctx.cgContext, images: images)
        }
    }
}
