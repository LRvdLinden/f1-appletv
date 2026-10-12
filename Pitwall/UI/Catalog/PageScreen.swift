import SwiftUI

/// A navigation stack rooted at a catalog page, with destinations for pages and sessions.
struct BrowseStack: View {
    let root: PageRef
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            PageScreen(ref: root, isRoot: true)
                .navigationDestination(for: PageRef.self) { PageScreen(ref: $0) }
                .navigationDestination(for: CatalogItem.self) { VideoDetailScreen(item: $0) }
        }
    }
}

struct PageScreen: View {
    @Environment(AppModel.self) private var model
    let ref: PageRef
    var isRoot = false

    @State private var page: CatalogPage?
    @State private var error: String?

    var body: some View {
        Group {
            if let page {
                if page.sections.isEmpty {
                    ErrorStateView(message: String(localized: "Hier is nog niets te zien.")) { Task { await load() } }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.rowSpacing) {
                            ForEach(page.sections) { section in
                                SectionView(section: section)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    #if !os(tvOS)
                    .refreshable { await load() }
                    #endif
                }
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .background(Theme.background)
        #if !os(tvOS)
        .navigationTitle(ref.title)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        #endif
        .task(id: "\(ref.uri)-\(model.settings.catalogLanguage.rawValue)") { await load() }
    }

    private func load() async {
        error = nil
        do {
            page = try await model.catalog.page(ref)
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            if page == nil { self.error = error.localizedDescription }
        }
    }
}
