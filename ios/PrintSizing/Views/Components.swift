import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A length shown and typed in the user's unit, stored in millimetres.
struct LengthField: View {
    let title: String
    var hint: String?
    @Binding var mm: Double
    let unit: LengthUnit
    var min: Double = 0

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Labelled(title: title, hint: hint)
            Spacer(minLength: 8)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(width: 64)
            Text(unit.label).foregroundStyle(.secondary)
        }
        .onAppear { text = formatted }
        .onChange(of: text) {
            // Only typing changes the value; reformatting it must not round it.
            guard focused, let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
            let next = unit.toMM(v)
            if next >= min, next <= 5000, abs(next - mm) > 1e-9 { mm = next }
        }
        .onChange(of: focused) { if !focused { text = formatted } }
        .onChange(of: mm) { if !focused { text = formatted } }
        .onChange(of: unit) { text = formatted }
    }

    private var formatted: String { formatNumber(unit.fromMM(mm), digits: unit.inputDigits) }
}

/// A row label with an optional grey hint underneath.
struct Labelled: View {
    let title: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Horizontally scrolling quick-pick buttons.
struct Chips<Value: Hashable>: View {
    let values: [Value]
    let label: (Value) -> String
    let isOn: (Value) -> Bool
    let pick: (Value) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { v in
                    Button(label(v)) { pick(v) }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOn(v) ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(isOn(v) ? Color.white : Color.primary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct UnitPicker: View {
    @Binding var unit: LengthUnit

    var body: some View {
        Picker("Units", selection: $unit) {
            ForEach(LengthUnit.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 160)
    }
}

struct OrientationPicker: View {
    @Binding var orientation: PageOrientation

    var body: some View {
        Picker("Orientation", selection: $orientation) {
            Text("Auto").tag(PageOrientation.auto)
            Text("Portrait").tag(PageOrientation.portrait)
            Text("Landscape").tag(PageOrientation.landscape)
        }
        .pickerStyle(.segmented)
    }
}

/// Paper size, plus width and height when it is custom.
struct PaperSection: View {
    @Binding var paper: String
    @Binding var customW: Double
    @Binding var customH: Double
    @Binding var orientation: PageOrientation
    let unit: LengthUnit

    var body: some View {
        Section("Paper") {
            Picker("Paper size", selection: $paper) {
                ForEach(Papers.all) { Text($0.name).tag($0.id) }
                Text("Custom").tag(Papers.customID)
            }
            if paper == Papers.customID {
                LengthField(title: "Paper width", mm: $customW, unit: unit, min: 20)
                LengthField(title: "Paper height", mm: $customH, unit: unit, min: 20)
            }
            LabeledContent("Orientation") {
                OrientationPicker(orientation: $orientation).frame(maxWidth: 230)
            }
        }
    }
}

/// Buttons to add images from Photos or Files.
struct ImageSourceButtons: View {
    var multiple: Bool
    var photosLabel = "Photos"
    var onPick: ([(data: Data, name: String)]) -> Void

    @State private var selection: [PhotosPickerItem] = []
    @State private var showFiles = false

    var body: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selection, maxSelectionCount: multiple ? nil : 1, matching: .images) {
                Label(photosLabel, systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                showFiles = true
            } label: {
                Label("Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: selection) {
            let items = selection
            guard !items.isEmpty else { return }
            selection = []
            Task {
                var files: [(data: Data, name: String)] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        files.append((data, item.itemIdentifier ?? "Photo"))
                    }
                }
                onPick(files)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: multiple) { result in
            guard case let .success(urls) = result else { return }
            let files: [(data: Data, name: String)] = urls.compactMap { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return (try? Data(contentsOf: url)).map { ($0, url.lastPathComponent) }
            }
            onPick(files)
        }
    }
}

/// A photo drawn with the user's rotation, filling its frame.
struct PhotoThumb: View {
    let photo: Photo

    var body: some View {
        Canvas { gc, size in
            let fit = fitted(aspect: photo.aspect, in: size)
            gc.withCGContext { cg in
                drawPhoto(cg, photo.preview, userRot: photo.rotation, crop: .full, placeRot: 0, in: fit)
            }
        }
    }
}

/// The largest rectangle of `aspect` centred in `size`.
func fitted(aspect: Double, in size: CGSize) -> CGRect {
    var w = size.width
    var h = w / aspect
    if h > size.height {
        h = size.height
        w = h * aspect
    }
    return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
}

/// UIKit share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
