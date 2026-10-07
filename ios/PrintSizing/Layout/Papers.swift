import Foundation

struct Paper: Identifiable, Hashable {
    let id: String
    let name: String
    let w: Double
    let h: Double
    /// Photo paper sizes default to photo-quality printing.
    let isPhoto: Bool

    var size: MMSize { MMSize(w: w, h: h) }
}

enum Papers {
    static let customID = "custom"

    // Stored portrait (w <= h); orientation is applied by the layout.
    static let all: [Paper] = [
        Paper(id: "a4", name: "A4", w: 210, h: 297, isPhoto: false),
        Paper(id: "letter", name: "US Letter", w: 215.9, h: 279.4, isPhoto: false),
        Paper(id: "4x6", name: "6 × 4 in photo", w: 101.6, h: 152.4, isPhoto: true),
        Paper(id: "5x7", name: "7 × 5 in photo", w: 127, h: 177.8, isPhoto: true),
        Paper(id: "10x15", name: "15 × 10 cm photo", w: 100, h: 150, isPhoto: true),
        Paper(id: "13x18", name: "18 × 13 cm photo", w: 130, h: 180, isPhoto: true),
        Paper(id: "8x10", name: "10 × 8 in photo", w: 203.2, h: 254, isPhoto: true),
        Paper(id: "a5", name: "A5", w: 148, h: 210, isPhoto: false),
        Paper(id: "a6", name: "A6", w: 105, h: 148, isPhoto: false),
        Paper(id: "a3", name: "A3", w: 297, h: 420, isPhoto: false),
        Paper(id: "legal", name: "US Legal", w: 215.9, h: 355.6, isPhoto: false),
    ]

    static func paper(id: String, customW: Double, customH: Double) -> Paper {
        if id == customID {
            let w = max(20, min(customW, customH))
            let h = max(20, max(customW, customH))
            return Paper(id: customID, name: "Custom", w: w, h: h, isPhoto: false)
        }
        return all.first { $0.id == id } ?? all[0]
    }
}

enum LengthUnit: String, Codable, CaseIterable, Identifiable {
    case inch = "in"
    case cm
    case mm

    var id: String { rawValue }
    var label: String { rawValue }

    var factor: Double {
        switch self {
        case .inch: return 25.4
        case .cm: return 10
        case .mm: return 1
        }
    }

    /// Decimals for read-only display.
    var digits: Int {
        switch self {
        case .inch: return 2
        case .cm: return 1
        case .mm: return 0
        }
    }

    /// Decimals in editable fields: enough for 5.08 cm or 1.38 in, no noise.
    var inputDigits: Int {
        switch self {
        case .inch: return 2
        case .cm: return 2
        case .mm: return 1
        }
    }

    func fromMM(_ mm: Double) -> Double { mm / factor }
    func toMM(_ v: Double) -> Double { v * factor }
}

/// At most `digits` decimals, without trailing zeros.
func formatNumber(_ v: Double, digits: Int) -> String {
    var s = String(format: "%.\(digits)f", v)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    return s == "-0" ? "0" : s
}

func formatLength(_ mm: Double, _ unit: LengthUnit) -> String {
    formatNumber(unit.fromMM(mm), digits: unit.digits)
}

func formatSize(_ w: Double, _ h: Double, _ unit: LengthUnit) -> String {
    "\(formatLength(w, unit)) × \(formatLength(h, unit)) \(unit.label)"
}

struct SizePreset: Identifiable, Hashable {
    let label: String
    let w: Double
    let h: Double
    var id: String { label }

    static let all: [SizePreset] = [
        SizePreset(label: "2 × 3 in", w: 50.8, h: 76.2),
        SizePreset(label: "2 × 2 in", w: 50.8, h: 50.8),
        SizePreset(label: "2.5 × 3.5 in", w: 63.5, h: 88.9),
        SizePreset(label: "3 × 4 in", w: 76.2, h: 101.6),
        SizePreset(label: "3.5 × 5 in", w: 88.9, h: 127),
        SizePreset(label: "4 × 6 in", w: 101.6, h: 152.4),
        SizePreset(label: "5 × 7 in", w: 127, h: 177.8),
        SizePreset(label: "35 × 45 mm passport", w: 35, h: 45),
        SizePreset(label: "5 × 5 cm", w: 50, h: 50),
    ]

    func matches(w: Double, h: Double) -> Bool {
        let same = { (a: Double, b: Double) in abs(a - b) < 0.05 }
        return (same(self.w, w) && same(self.h, h)) || (same(self.w, h) && same(self.h, w))
    }
}
