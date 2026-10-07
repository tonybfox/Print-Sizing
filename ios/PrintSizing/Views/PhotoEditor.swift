import SwiftUI

/// Choose the crop (drag, pinch or slider), rotate, set copies, or remove a photo.
struct PhotoEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let photo: Photo

    @State private var lastDrag: CGSize = .zero
    @State private var zoomStart: Double?

    private var isPoster: Bool { photo === model.posterPhoto }

    var body: some View {
        let aspect = model.cropAspect(for: photo, in: model.plan)
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    cropArea(aspect: aspect, size: geo.size)
                }
                .padding(12)
                .background(Color.black, ignoresSafeAreaEdges: [])

                Form {
                    Section {
                        if aspect != nil {
                            LabeledContent("Zoom") {
                                Slider(value: zoomBinding(aspect), in: 1...6)
                                    .frame(maxWidth: 220)
                            }
                        }
                        LabeledContent("Rotate") {
                            HStack(spacing: 8) {
                                Button { photo.rotate(by: -90) } label: { Image(systemName: "rotate.left") }
                                    .accessibilityLabel("Rotate left")
                                Button { photo.rotate(by: 90) } label: { Image(systemName: "rotate.right") }
                                    .accessibilityLabel("Rotate right")
                            }
                            .buttonStyle(.bordered)
                        }
                        if !isPoster {
                            Stepper(value: Binding(get: { photo.copies }, set: { photo.copies = $0 }), in: 1...200) {
                                LabeledContent("Copies", value: "\(photo.copies)")
                            }
                        }
                    } footer: {
                        Text(aspect != nil
                             ? "Drag to choose what gets printed. Pinch or use the slider to zoom in."
                             : isPoster
                             ? "The whole image is printed. To crop, choose Pages and turn on “Fill every page”."
                             : "The whole photo is printed. Choose “Fill & crop” under Layout to fill the space and pick the crop.")
                    }
                    Section {
                        if aspect != nil {
                            Button("Reset crop") { photo.adjust = CropAdjust() }
                        }
                        if !isPoster {
                            Button("Remove photo", role: .destructive) {
                                model.remove(photo)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isPoster ? "Poster image" : "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func cropArea(aspect: Double?, size: CGSize) -> some View {
        let r = fitted(aspect: photo.aspect, in: size)
        return Canvas { gc, _ in
            gc.withCGContext { cg in
                drawPhoto(cg, photo.preview, userRot: photo.rotation, crop: .full, placeRot: 0,
                          in: CGRect(origin: .zero, size: r.size))
            }
            guard let aspect else { return }
            let c = computeCrop(imageAspect: photo.aspect, targetAspect: aspect, adjust: photo.adjust)
            let win = CGRect(x: c.x * r.width, y: c.y * r.height, width: c.w * r.width, height: c.h * r.height)
            var shade = Path(CGRect(origin: .zero, size: r.size))
            shade.addRect(win)
            gc.fill(shade, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            var thirds = Path()
            for f in [1.0 / 3, 2.0 / 3] {
                thirds.move(to: CGPoint(x: win.minX + win.width * f, y: win.minY))
                thirds.addLine(to: CGPoint(x: win.minX + win.width * f, y: win.maxY))
                thirds.move(to: CGPoint(x: win.minX, y: win.minY + win.height * f))
                thirds.addLine(to: CGPoint(x: win.maxX, y: win.minY + win.height * f))
            }
            gc.stroke(thirds, with: .color(.white.opacity(0.4)), lineWidth: 1)
            gc.stroke(Path(win.insetBy(dx: 1, dy: 1)), with: .color(.white), lineWidth: 2)
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .gesture(aspect == nil ? nil : panGesture(aspect!, size: r.size).simultaneously(with: zoomGesture(aspect!)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func panGesture(_ aspect: Double, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.translation.width - lastDrag.width
                let dy = v.translation.height - lastDrag.height
                lastDrag = v.translation
                var a = photo.adjust
                a.cx += dx / size.width
                a.cy += dy / size.height
                photo.adjust = clampAdjust(a, imageAspect: photo.aspect, targetAspect: aspect)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private func zoomGesture(_ aspect: Double) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let start = zoomStart ?? photo.adjust.zoom
                zoomStart = start
                var a = photo.adjust
                a.zoom = start * v.magnification
                photo.adjust = clampAdjust(a, imageAspect: photo.aspect, targetAspect: aspect)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func zoomBinding(_ aspect: Double?) -> Binding<Double> {
        Binding(get: { photo.adjust.zoom }, set: { z in
            var a = photo.adjust
            a.zoom = z
            photo.adjust = aspect.map { clampAdjust(a, imageAspect: photo.aspect, targetAspect: $0) } ?? a
        })
    }
}
