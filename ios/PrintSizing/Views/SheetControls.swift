import SwiftUI

struct SheetControls: View {
    @Environment(AppModel.self) private var model
    var onEdit: (Photo) -> Void
    var onAdd: ([(data: Data, name: String)]) -> Void

    @State private var confirmClear = false

    var body: some View {
        @Bindable var model = model
        let unit = model.unit

        Section {
            ImageSourceButtons(multiple: true, onPick: onAdd)
            if !model.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.photos) { p in
                            Button { onEdit(p) } label: {
                                PhotoThumb(photo: p)
                                    .frame(width: 64, height: 64)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        if p.copies > 1 {
                                            Text("×\(p.copies)")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.65), in: Capsule())
                                                .foregroundStyle(.white)
                                                .padding(3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit photo")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Photos")
                Spacer()
                if !model.photos.isEmpty {
                    Button("Clear all") { confirmClear = true }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        } footer: {
            Text("Tap a photo to crop, rotate or print extra copies.")
        }
        .confirmationDialog("Remove all photos?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) { model.photos.removeAll() }
        }

        Section("Size") {
            Picker("Sizing", selection: $model.settings.sheet.sizing) {
                Text("Photos per page").tag(Sizing.count)
                Text("Exact size").tag(Sizing.exact)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if model.settings.sheet.sizing == .count {
                Stepper(value: $model.settings.sheet.perPage, in: 1...100) {
                    LabeledContent("Photos per page", value: "\(model.settings.sheet.perPage)")
                }
                Chips(values: [1, 2, 3, 4, 6, 8, 9, 12, 16, 20], label: { "\($0)" },
                      isOn: { $0 == model.settings.sheet.perPage },
                      pick: { model.settings.sheet.perPage = $0 })
            } else {
                LengthField(title: "Width", mm: $model.settings.sheet.pieceW, unit: unit, min: 1)
                LengthField(title: "Height", mm: $model.settings.sheet.pieceH, unit: unit, min: 1)
                Button {
                    swap(&model.settings.sheet.pieceW, &model.settings.sheet.pieceH)
                } label: {
                    Label("Swap width and height", systemImage: "arrow.left.arrow.right")
                }
                Chips(values: SizePreset.all, label: \.label,
                      isOn: { $0.matches(w: model.settings.sheet.pieceW, h: model.settings.sheet.pieceH) },
                      pick: {
                          model.settings.sheet.pieceW = $0.w
                          model.settings.sheet.pieceH = $0.h
                      })
                LabeledContent("Units") { UnitPicker(unit: $model.settings.unit) }
                Toggle(isOn: $model.settings.sheet.matchOrientation) {
                    Labelled(title: "Match each photo's shape",
                             hint: "Landscape photos print sideways (e.g. 3 × 2 instead of 2 × 3)")
                }
            }
        }

        PaperSection(paper: $model.settings.sheet.paper, customW: $model.settings.sheet.customW,
                     customH: $model.settings.sheet.customH, orientation: $model.settings.sheet.orientation, unit: unit)

        Section("Layout") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Photo fit", selection: $model.settings.sheet.fill) {
                    Text("Whole photo").tag(false)
                    Text("Fill & crop").tag(true)
                }
                .pickerStyle(.segmented)
                Text(model.settings.sheet.fill ? "Fills the space; edges may be cropped" : "Keeps the whole photo; may leave white space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.settings.sheet.sizing == .count {
                Toggle("Turn photos to fit best", isOn: $model.settings.sheet.autoRotate)
            }
            LengthField(title: "Page margin", hint: "Keep at least 3–5 mm unless printing borderless",
                        mm: $model.settings.sheet.margin, unit: unit)
            LengthField(title: "Space between photos", mm: $model.settings.sheet.gap, unit: unit)
            Picker("Cut guides", selection: $model.settings.sheet.guides) {
                Text("None").tag(CutGuides.none)
                Text("Thin outline").tag(CutGuides.outline)
                Text("Corner marks").tag(CutGuides.marks)
            }
            Toggle(isOn: $model.settings.sheet.fillPage) {
                Labelled(title: "Fill the page with copies", hint: "Repeats your photos to use every space")
            }
        }

        PrinterSection()
    }
}

struct PrinterSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(isOn: $model.photoPaper) {
                Labelled(title: "Photo paper", hint: "Uses the printer's photo quality settings")
            }
        } header: {
            Text("Printer")
        } footer: {
            Text("A margin of 0 prints borderless where the printer supports it.")
        }
    }
}
