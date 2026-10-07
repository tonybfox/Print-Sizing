import Foundation
import Observation

/// What is currently laid out, in either mode.
struct Plan {
    var pages: [Page]
    var error: LayoutError?
    var sheet: SheetInfo?
    var poster: PosterInfo?

    var orientation: PageOrientation? { sheet?.orientation ?? poster?.orientation }
    var hasPhotos: Bool { pages.contains { !$0.items.isEmpty } }
}

@MainActor
@Observable
final class AppModel {
    var settings = Settings.load() {
        didSet { if settings != oldValue { settings.save() } }
    }
    var photos: [Photo] = []
    var posterPhoto: Photo?

    var mode: Mode {
        get { settings.mode }
        set { settings.mode = newValue }
    }

    var unit: LengthUnit { settings.unit }

    // MARK: Papers

    var sheetPaper: Paper { Papers.paper(id: settings.sheet.paper, customW: settings.sheet.customW, customH: settings.sheet.customH) }
    var posterPaper: Paper { Papers.paper(id: settings.poster.paper, customW: settings.poster.customW, customH: settings.poster.customH) }
    var currentPaper: Paper { mode == .sheet ? sheetPaper : posterPaper }
    var currentMargin: Double { mode == .sheet ? settings.sheet.margin : settings.poster.margin }

    func paperLabel(_ paper: Paper, _ orientation: PageOrientation? = nil) -> String {
        let name = paper.id == Papers.customID ? formatSize(paper.w, paper.h, unit) : paper.name
        guard let o = orientation, o != .auto else { return name }
        return "\(name) \(o.rawValue)"
    }

    /// Print with the printer's photo-paper settings.
    var photoPaper: Bool {
        get { settings.photoPaper[currentPaper.id] ?? currentPaper.isPhoto }
        set { settings.photoPaper[currentPaper.id] = newValue }
    }

    // MARK: Layout

    var plan: Plan {
        if mode == .sheet {
            let s = settings.sheet
            let r = buildSheet(SheetOptions(
                paper: sheetPaper.size, orientation: s.orientation, margin: s.margin, gap: s.gap,
                sizing: s.sizing, perPage: s.perPage, pieceW: s.pieceW, pieceH: s.pieceH, fill: s.fill,
                autoRotate: s.autoRotate, matchOrientation: s.matchOrientation, guides: s.guides,
                fillPage: s.fillPage, photos: photos.map(\.ref)))
            return Plan(pages: r.pages, error: r.error, sheet: r.info)
        }
        let p = settings.poster
        let r = buildPoster(PosterOptions(
            paper: posterPaper.size, orientation: p.orientation, margin: p.margin, overlap: p.overlap,
            sizeBy: p.sizeBy, cols: p.cols, rows: p.rows, width: p.width, height: p.height,
            fill: p.fill, guides: p.guides, photo: posterPhoto?.ref))
        return Plan(pages: r.pages, error: r.error, poster: r.info)
    }

    func photo(id: Int) -> Photo? {
        if let p = posterPhoto, p.id == id { return p }
        return photos.first { $0.id == id }
    }

    /// Shape of the crop window for a photo, or nil when it is printed whole.
    func cropAspect(for photo: Photo, in plan: Plan) -> Double? {
        if photo === posterPhoto {
            guard mode == .poster, settings.poster.sizeBy == .grid, settings.poster.fill, let i = plan.poster else { return nil }
            return i.posterW / i.posterH
        }
        guard mode == .sheet, settings.sheet.fill else { return nil }
        for page in plan.pages {
            for it in page.items where it.photoID == photo.id {
                return it.rot != 0 ? it.rect.h / it.rect.w : it.rect.w / it.rect.h
            }
        }
        return nil
    }

    // MARK: Text

    func caption(_ plan: Plan) -> String {
        if let e = plan.error { return errorText(e) }
        if let i = plan.sheet {
            let s = settings.sheet
            if s.sizing == .exact {
                let turned = plan.pages.contains { $0.items.contains { $0.rot != 0 } }
                return "\(i.perPage) per page · each \(formatSize(s.pieceW, s.pieceH, unit))\(turned ? " · some turned to fit more" : "")"
            }
            let each = s.fill ? "each" : "each up to"
            return "\(i.perPage) per page (\(i.cols ?? 1) × \(i.rows ?? 1)) · \(each) \(formatSize(i.slotW, i.slotH, unit))"
        }
        if let i = plan.poster {
            return "Finished size \(formatSize(i.posterW, i.posterH, unit)) · \(i.cols) across × \(i.rows) down"
        }
        return ""
    }

    func errorText(_ e: LayoutError) -> String {
        let paper = paperLabel(currentPaper)
        switch e {
        case let .tooBig(cw, ch):
            let s = settings.sheet
            return "\(formatSize(s.pieceW, s.pieceH, unit)) won't fit on \(paper) with these margins (room for \(formatSize(cw, ch, unit)))."
        case let .tooMany(n):
            return "That needs \(n) pages. Try a smaller size or bigger paper."
        case .margins:
            let overlap = mode == .poster && settings.poster.overlap > 0
            return "The margins\(overlap ? " and overlap" : "") are too big for \(paper)."
        }
    }

    func summary(_ plan: Plan) -> String {
        let n = plan.pages.count
        return "\(n) page\(n == 1 ? "" : "s") · \(paperLabel(currentPaper, plan.orientation))"
    }

    var jobName: String {
        mode == .sheet ? "Photos" : "Poster"
    }

    var pdfName: String {
        let paper = currentPaper.id == Papers.customID ? "custom" : currentPaper.name.filter { $0.isLetter || $0.isNumber }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let stamp = f.string(from: Date())
        if mode == .poster, let i = plan.poster { return "poster-\(i.cols)x\(i.rows)-\(paper)-\(stamp).pdf" }
        return "photos-\(paper)-\(stamp).pdf"
    }

    // MARK: Photos

    /// Opens image files off the main thread. Returns the photos that could be read.
    nonisolated static func open(_ files: [(data: Data, name: String)]) async -> [Photo] {
        await Task.detached(priority: .userInitiated) {
            files.compactMap { try? Photo(data: $0.data, name: $0.name) }
        }.value
    }

    func remove(_ photo: Photo) {
        photos.removeAll { $0 === photo }
    }
}
