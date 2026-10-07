import Foundation

enum Mode: String, Codable {
    case sheet, poster
}

struct SheetSettings: Codable, Equatable {
    var paper = "a4"
    var customW = 210.0
    var customH = 297.0
    var orientation = PageOrientation.auto
    var sizing = Sizing.count
    var perPage = 6
    var pieceW = 50.8
    var pieceH = 76.2
    /// Fill & crop (true) or whole photo, separately for each sizing.
    var fillCount = false
    var fillExact = true
    var autoRotate = true
    var matchOrientation = true
    var margin = 5.0
    var gap = 3.0
    var guidesCount = CutGuides.none
    var guidesExact = CutGuides.outline
    var fillPage = false

    var fill: Bool {
        get { sizing == .exact ? fillExact : fillCount }
        set { if sizing == .exact { fillExact = newValue } else { fillCount = newValue } }
    }

    var guides: CutGuides {
        get { sizing == .exact ? guidesExact : guidesCount }
        set { if sizing == .exact { guidesExact = newValue } else { guidesCount = newValue } }
    }
}

struct PosterSettings: Codable, Equatable {
    var paper = "a4"
    var customW = 210.0
    var customH = 297.0
    var orientation = PageOrientation.auto
    var sizeBy = PosterSizeBy.grid
    var cols = 2
    var rows = 2
    var width = 600.0
    var height = 800.0
    var fill = false
    var margin = 6.0
    var overlap = 0.0
    var guides = true
}

struct Settings: Codable, Equatable {
    var mode = Mode.sheet
    var unit = LengthUnit.inch
    var dpi = 300
    var sheet = SheetSettings()
    var poster = PosterSettings()
    /// Photo paper choices the user changed, by paper id. Unset means the paper's own default.
    var photoPaper: [String: Bool] = [:]

    private static let key = "print-sizing:settings:v1"

    static func load() -> Settings {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            return saved
        }
        var s = Settings()
        if let region = Locale.current.region?.identifier, ["US", "CA"].contains(region) {
            s.sheet.paper = "letter"
            s.poster.paper = "letter"
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Settings.key)
        }
    }
}

// Missing keys fall back to defaults, so settings saved by an older version still load.
extension SheetSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SheetSettings()
        paper = try c.decodeIfPresent(String.self, forKey: .paper) ?? d.paper
        customW = try c.decodeIfPresent(Double.self, forKey: .customW) ?? d.customW
        customH = try c.decodeIfPresent(Double.self, forKey: .customH) ?? d.customH
        orientation = try c.decodeIfPresent(PageOrientation.self, forKey: .orientation) ?? d.orientation
        sizing = try c.decodeIfPresent(Sizing.self, forKey: .sizing) ?? d.sizing
        perPage = try c.decodeIfPresent(Int.self, forKey: .perPage) ?? d.perPage
        pieceW = try c.decodeIfPresent(Double.self, forKey: .pieceW) ?? d.pieceW
        pieceH = try c.decodeIfPresent(Double.self, forKey: .pieceH) ?? d.pieceH
        fillCount = try c.decodeIfPresent(Bool.self, forKey: .fillCount) ?? d.fillCount
        fillExact = try c.decodeIfPresent(Bool.self, forKey: .fillExact) ?? d.fillExact
        autoRotate = try c.decodeIfPresent(Bool.self, forKey: .autoRotate) ?? d.autoRotate
        matchOrientation = try c.decodeIfPresent(Bool.self, forKey: .matchOrientation) ?? d.matchOrientation
        margin = try c.decodeIfPresent(Double.self, forKey: .margin) ?? d.margin
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? d.gap
        guidesCount = try c.decodeIfPresent(CutGuides.self, forKey: .guidesCount) ?? d.guidesCount
        guidesExact = try c.decodeIfPresent(CutGuides.self, forKey: .guidesExact) ?? d.guidesExact
        fillPage = try c.decodeIfPresent(Bool.self, forKey: .fillPage) ?? d.fillPage
    }
}

extension PosterSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PosterSettings()
        paper = try c.decodeIfPresent(String.self, forKey: .paper) ?? d.paper
        customW = try c.decodeIfPresent(Double.self, forKey: .customW) ?? d.customW
        customH = try c.decodeIfPresent(Double.self, forKey: .customH) ?? d.customH
        orientation = try c.decodeIfPresent(PageOrientation.self, forKey: .orientation) ?? d.orientation
        sizeBy = try c.decodeIfPresent(PosterSizeBy.self, forKey: .sizeBy) ?? d.sizeBy
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? d.cols
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? d.rows
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? d.height
        fill = try c.decodeIfPresent(Bool.self, forKey: .fill) ?? d.fill
        margin = try c.decodeIfPresent(Double.self, forKey: .margin) ?? d.margin
        overlap = try c.decodeIfPresent(Double.self, forKey: .overlap) ?? d.overlap
        guides = try c.decodeIfPresent(Bool.self, forKey: .guides) ?? d.guides
    }
}

extension Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? d.mode
        unit = try c.decodeIfPresent(LengthUnit.self, forKey: .unit) ?? d.unit
        dpi = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? d.dpi
        sheet = try c.decodeIfPresent(SheetSettings.self, forKey: .sheet) ?? d.sheet
        poster = try c.decodeIfPresent(PosterSettings.self, forKey: .poster) ?? d.poster
        photoPaper = try c.decodeIfPresent([String: Bool].self, forKey: .photoPaper) ?? d.photoPaper
    }
}
