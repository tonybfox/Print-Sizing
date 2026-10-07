import CoreGraphics
import Foundation
import ImageIO
import Observation

/// A photo the user added: the original file, a small preview, and their edits.
@Observable
final class Photo: Identifiable {
    let id: Int
    let name: String
    /// Original file, decoded again at print resolution when printing.
    let data: Data
    /// EXIF orientation applied, at most `previewMax` px on the long side.
    let preview: CGImage
    /// Pixel size with EXIF orientation applied.
    let pixelWidth: Double
    let pixelHeight: Double

    /// User's clockwise turn: 0, 90, 180 or 270.
    var rotation = 0
    var adjust = CropAdjust()
    var copies = 1

    static let previewMax = 1200

    private static var nextID = 1

    enum LoadError: Error {
        case unreadable
    }

    init(data: Data, name: String) throws {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              var w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0,
              let preview = Photo.decode(src, maxPixels: Photo.previewMax)
        else { throw LoadError.unreadable }
        // EXIF orientations 5–8 are a quarter turn.
        if let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue, o >= 5 { swap(&w, &h) }
        id = Photo.nextID
        Photo.nextID += 1
        self.name = name
        self.data = data
        self.preview = preview
        pixelWidth = w
        pixelHeight = h
    }

    /// Width / height after the user's rotation.
    var aspect: Double { orientedAspect(width: pixelWidth, height: pixelHeight, rotation: rotation) }

    var ref: PhotoRef {
        PhotoRef(id: id, aspect: aspect, copies: copies, rotation: rotation, adjust: adjust)
    }

    func rotate(by delta: Int) {
        rotation = ((rotation + delta) % 360 + 360) % 360
        adjust = CropAdjust()
    }

    /// Decode at `longSide` pixels (never more than the original) for printing.
    func decode(longSide: Double) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let full = max(pixelWidth, pixelHeight)
        if longSide <= Double(max(preview.width, preview.height)) { return preview }
        return Photo.decode(src, maxPixels: Int(min(full, longSide).rounded(.up)))
    }

    private static func decode(_ src: CGImageSource, maxPixels: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
