import SwiftUI
import AppKit

/// ViewModel for clipboard history list
@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var selectedItemId: Int64?
    @Published var error: String?
    
    private let pageSize = 50
    private var currentOffset = 0
    private var loadGeneration: UInt64 = 0
    private var pageQuery = ""
    private var copyRequest: UInt64 = 0
    private let injectedStorage: StorageManager?
    private let injectedPasteboard: NSPasteboard?

    // Resolve production singletons only when an action needs them, never at host startup.
    private var storage: StorageManager { injectedStorage ?? .shared }
    private var pasteboard: NSPasteboard { injectedPasteboard ?? .general }

    init() {
        injectedStorage = nil
        injectedPasteboard = nil
    }

    init(storage: StorageManager, pasteboard: NSPasteboard) {
        injectedStorage = storage
        injectedPasteboard = pasteboard
    }
    
    // MARK: - Loading
    
    func loadInitial() async {
        loadGeneration &+= 1
        pageQuery = searchQuery
        currentOffset = 0
        hasMore = true
        items = []
        error = nil

        await loadPage()
    }

    func loadMore() async {
        guard !isLoading, hasMore, searchQuery == pageQuery else { return }
        await loadPage()
    }

    private func loadPage() async {
        let generation = loadGeneration
        let query = pageQuery
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let newItems: [ClipItem]
            if query.isEmpty {
                newItems = try await storage.fetchItems(limit: pageSize, offset: currentOffset)
            } else {
                newItems = try await storage.search(query: query, limit: pageSize, offset: currentOffset)
            }
            guard generation == loadGeneration, query == searchQuery else { return }
            items.append(contentsOf: newItems)
            currentOffset += newItems.count
            hasMore = newItems.count >= pageSize
        } catch {
            guard generation == loadGeneration, query == searchQuery else { return }
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        await loadInitial()
    }
    
    func search() async {
        await loadInitial()
    }
    
    // MARK: - Actions

    func exportSelected(_ ids: Set<Int64>, to directory: URL) async throws -> ExportService.ExportResult {
        let hasScopedAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { directory.stopAccessingSecurityScopedResource() }
        }
        return try await ExportService(storage: storage).exportNewFolder(
            scope: .selected(ids.sorted()), format: .markdown, includeImageRefs: true,
            destinationDir: ExportDestinationPicker.uniqueExportDirectory(inside: directory)
        )
    }
    
    func copyToClipboard(_ item: ClipItem, completion: @escaping (Bool) -> Void = { _ in }) {
        copyRequest &+= 1
        let request = copyRequest
        let pasteboard = self.pasteboard

        switch item.type {
        case .text:
            guard let text = item.textContent else {
                completion(false)
                return
            }
            pasteboard.clearContents()
            completion(pasteboard.setString(text, forType: .string))
        case .image:
            guard let imagePath = item.imagePath else {
                completion(false)
                return
            }
            let changeCount = pasteboard.changeCount
            Task {
                let url = await storage.imageURL(for: imagePath)
                guard request == copyRequest,
                      let image = NSImage(contentsOf: url), image.isValid,
                      pasteboard.changeCount == changeCount else {
                    completion(false)
                    return
                }
                pasteboard.clearContents()
                completion(pasteboard.writeObjects([image]))
            }
        }
    }

    func deleteItem(_ item: ClipItem) async {
        do {
            try await storage.delete(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func togglePinned(_ item: ClipItem) async {
        do {
            try await storage.togglePinned(id: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].pinned.toggle()
            }
            // Re-sort to move pinned items to top
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func clearHistory(keepPinned: Bool) async {
        do {
            try await storage.clearAll(keepPinned: keepPinned)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Keyboard Navigation
    
    func selectPrevious() {
        guard !items.isEmpty else { return }
        
        if let currentId = selectedItemId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }),
           currentIndex > 0 {
            selectedItemId = items[currentIndex - 1].id
        } else {
            selectedItemId = items.first?.id
        }
    }
    
    func selectNext() {
        guard !items.isEmpty else { return }
        
        if let currentId = selectedItemId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }),
           currentIndex < items.count - 1 {
            selectedItemId = items[currentIndex + 1].id
        } else {
            selectedItemId = items.first?.id
        }
    }
    
    func copySelected() {
        if let selectedId = selectedItemId,
           let item = items.first(where: { $0.id == selectedId }) {
            copyToClipboard(item)
        }
    }
    
    func deleteSelected() async {
        if let selectedId = selectedItemId,
           let item = items.first(where: { $0.id == selectedId }) {
            await deleteItem(item)
        }
    }
    
    func togglePinnedSelected() async {
        if let selectedId = selectedItemId,
           let item = items.first(where: { $0.id == selectedId }) {
            await togglePinned(item)
        }
    }
    
    var selectedItem: ClipItem? {
        items.first { $0.id == selectedItemId }
    }
}
