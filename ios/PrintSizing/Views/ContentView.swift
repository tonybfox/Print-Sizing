import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    @State private var editing: Photo?
    @State private var showSettings = false
    @State private var busy: String?
    @State private var toast: String?
    @State private var shareURL: URL?

    var body: some View {
        @Bindable var model = model
        let plan = model.plan

        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    PreviewPane(plan: plan, onTapPhoto: { editing = $0 }, onTapEmpty: {})
                        .frame(height: geo.size.height * 0.38)
                    Divider()
                    Form {
                        if model.mode == .sheet {
                            SheetControls(onEdit: { editing = $0 }, onAdd: addPhotos)
                        } else {
                            PosterControls(onEdit: { editing = $0 }, onPick: setPoster)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(plan) }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $model.mode) {
                        Text("Photo sheet").tag(Mode.sheet)
                        Text("Poster").tag(Mode.poster)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", action: hideKeyboard)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $editing) { photo in
            PhotoEditor(photo: photo)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        }
        .overlay { busyOverlay }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: Bottom bar

    private func bottomBar(_ plan: Plan) -> some View {
        let ready = plan.error == nil && plan.hasPhotos
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if ready {
                    Text(model.summary(plan)).font(.subheadline.weight(.semibold))
                    if let i = plan.sheet {
                        Text("\(i.photoCount) photo\(i.photoCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                } else if plan.error == nil {
                    Text(model.mode == .sheet ? "Add photos to get started" : "Choose an image to get started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await sharePDF(plan) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!ready)
            .accessibilityLabel("Share PDF")
            Button {
                Task { await printPages(plan) }
            } label: {
                Label("Print", systemImage: "printer").padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!ready)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Actions

    private func addPhotos(_ files: [(data: Data, name: String)]) {
        guard !files.isEmpty else { return }
        Task {
            busy = files.count > 1 ? "Adding \(files.count) photos…" : "Adding photo…"
            let photos = await AppModel.open(files)
            busy = nil
            model.photos.append(contentsOf: photos)
            reportFailures(files.count - photos.count, of: files.count)
        }
    }

    private func setPoster(_ files: [(data: Data, name: String)]) {
        guard let file = files.first else { return }
        Task {
            busy = "Adding image…"
            let photos = await AppModel.open([file])
            busy = nil
            if let p = photos.first { model.posterPhoto = p } else { reportFailures(1, of: 1) }
        }
    }

    private func reportFailures(_ failed: Int, of total: Int) {
        guard failed > 0 else { return }
        show(failed == 1 && total == 1 ? "That file couldn't be opened." : "\(failed) file\(failed > 1 ? "s" : "") couldn't be opened.")
    }

    private func printImages(_ plan: Plan) async -> PrintImages {
        let photos = model.mode == .sheet ? model.photos : [model.posterPhoto].compactMap { $0 }
        let images = PrintImages(pages: plan.pages, photos: photos, dpi: Double(model.settings.dpi))
        busy = "Preparing photos…"
        await Task.detached(priority: .userInitiated) { images.prepare() }.value
        busy = nil
        return images
    }

    private func printPages(_ plan: Plan) async {
        let images = await printImages(plan)
        let job = PrintJob(pages: plan.pages, margin: model.currentMargin, images: images)
        job.present(jobName: model.jobName, photoPaper: model.photoPaper) { error in
            if let error { show("Couldn't print: \(error.localizedDescription)") }
        }
    }

    private func sharePDF(_ plan: Plan) async {
        let images = await printImages(plan)
        busy = "Making PDF…"
        let title = model.jobName
        let pages = plan.pages
        let data = await Task.detached(priority: .userInitiated) { makePDF(pages: pages, images: images, title: title) }.value
        busy = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(model.pdfName)
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            show("Couldn't make the PDF: \(error.localizedDescription)")
        }
    }

    // MARK: Busy and toast

    @ViewBuilder
    private var busyOverlay: some View {
        if let busy {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(busy).font(.subheadline)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 90)
                .transition(.opacity)
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toast == message { withAnimation { toast = nil } }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
