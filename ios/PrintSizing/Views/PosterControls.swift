import SwiftUI

struct PosterControls: View {
    @Environment(AppModel.self) private var model
    var onEdit: (Photo) -> Void
    var onPick: ([(data: Data, name: String)]) -> Void

    var body: some View {
        @Bindable var model = model
        let unit = model.unit

        Section("Image") {
            if let p = model.posterPhoto {
                HStack(spacing: 12) {
                    Button { onEdit(p) } label: {
                        PhotoThumb(photo: p)
                            .frame(width: 72, height: 72)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rotate or crop the image")
                    Button("Rotate / crop") { onEdit(p) }
                        .buttonStyle(.bordered)
                }
            }
            ImageSourceButtons(multiple: false, photosLabel: model.posterPhoto == nil ? "Photos" : "Change", onPick: onPick)
        }

        Section("Poster size") {
            Picker("Size by", selection: $model.settings.poster.sizeBy) {
                Text("Pages").tag(PosterSizeBy.grid)
                Text("Width").tag(PosterSizeBy.width)
                Text("Height").tag(PosterSizeBy.height)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            switch model.settings.poster.sizeBy {
            case .grid:
                Stepper(value: $model.settings.poster.cols, in: 1...20) {
                    LabeledContent("Pages across", value: "\(model.settings.poster.cols)")
                }
                Stepper(value: $model.settings.poster.rows, in: 1...20) {
                    LabeledContent("Pages down", value: "\(model.settings.poster.rows)")
                }
                Toggle(isOn: $model.settings.poster.fill) {
                    Labelled(title: "Fill every page", hint: "Crops the image to the shape of the pages")
                }
            case .width:
                LengthField(title: "Finished width", mm: $model.settings.poster.width, unit: unit, min: 10)
            case .height:
                LengthField(title: "Finished height", mm: $model.settings.poster.height, unit: unit, min: 10)
            }
            LabeledContent("Units") { UnitPicker(unit: $model.settings.unit) }
        }

        PaperSection(paper: $model.settings.poster.paper, customW: $model.settings.poster.customW,
                     customH: $model.settings.poster.customH, orientation: $model.settings.poster.orientation, unit: unit)

        Section("Joining the pages") {
            LengthField(title: "Page margin", hint: "Most printers can't print the outer 3–5 mm",
                        mm: $model.settings.poster.margin, unit: unit)
            LengthField(title: "Overlap", hint: "Repeat a strip on the next page to glue under",
                        mm: $model.settings.poster.overlap, unit: unit)
            Toggle("Trim marks & page labels", isOn: $model.settings.poster.guides)
            DisclosureGroup("How to put it together") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Each page is labelled (A1, A2, B1…) with a little map showing where it goes. Row A is the top.")
                    Text("2. **No overlap:** trim the margins off along the corner marks and butt the pages edge to edge, taping on the back.")
                    Text("3. **With overlap:** trim the top and left margins of each page (except row A and column 1), then lay it over its neighbour so its edge sits on the dashed marks. Glue or tape.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }

        PrinterSection()
    }
}
