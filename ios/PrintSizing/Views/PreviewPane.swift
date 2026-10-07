import SwiftUI

/// The pages as they will print: swipe between sheet pages, or the assembled poster.
struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    let plan: Plan
    var onTapPhoto: (Photo) -> Void
    var onTapEmpty: () -> Void

    @State private var pageIndex = 0

    private let maxPages = 40

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                content(in: geo.size)
            }
            VStack(spacing: 2) {
                Text(model.caption(plan))
                    .font(.footnote)
                    .foregroundStyle(plan.error != nil ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if model.mode == .sheet, plan.pages.count > 1 {
                    Text("Page \(min(pageIndex, plan.pages.count - 1) + 1) of \(plan.pages.count)\(plan.pages.count > maxPages ? " (first \(maxPages) shown)" : "")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if plan.error != nil {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.mode == .poster, let info = plan.poster {
            posterView(info, in: size)
        } else {
            let pages = Array(plan.pages.prefix(maxPages))
            TabView(selection: $pageIndex) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i], in: size).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: plan.pages.count) {
                if pageIndex >= plan.pages.count { pageIndex = max(0, plan.pages.count - 1) }
            }
        }
    }

    private func pageView(_ page: Page, in size: CGSize) -> some View {
        let r = fitted(aspect: page.w / page.h, in: CGSize(width: size.width - 48, height: size.height - 20))
        let k = r.width / page.w
        return Canvas { gc, _ in
            gc.withCGContext { cg in
                PageDrawer(scale: k, minLineWidth: 0.75) { model.photo(id: $0.photoID)?.preview }.draw(page, in: cg)
            }
        }
        .frame(width: r.width, height: r.height)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { p in
            let x = p.x / k
            let y = p.y / k
            let hit = page.items.first { x >= $0.rect.x && x <= $0.rect.x + $0.rect.w && y >= $0.rect.y && y <= $0.rect.y + $0.rect.h }
            if let hit, let photo = model.photo(id: hit.photoID) {
                onTapPhoto(photo)
            } else if model.photos.isEmpty {
                onTapEmpty()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Page preview")
    }

    private func posterView(_ info: PosterInfo, in size: CGSize) -> some View {
        let grid = posterGridSize(info)
        let r = fitted(aspect: grid.width / grid.height, in: CGSize(width: size.width - 32, height: size.height - 16))
        let k = r.width / grid.width
        return Canvas { gc, _ in
            gc.withCGContext { cg in
                drawPosterPreview(cg, plan: plan, photo: model.posterPhoto, k: k)
            }
        }
        .frame(width: r.width, height: r.height)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if let p = model.posterPhoto { onTapPhoto(p) } else { onTapEmpty() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Poster preview")
    }
}
