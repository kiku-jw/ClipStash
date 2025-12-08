import SwiftUI

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
    
    // MARK: - Loading
    
    func loadInitial() async {
        currentOffset = 0
        hasMore = true
        items = []
        
        await loadMore()
    }
    
    func loadMore() async {
        guard !isLoading, hasMore else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let newItems: [ClipItem]
            
            if searchQuery.isEmpty {
                newItems = try await StorageManager.shared.fetchItems(limit: pageSize, offset: currentOffset)
            } else {
                newItems = try await StorageManager.shared.search(query: searchQuery, limit: pageSize, offset: currentOffset)
            }
            
            items.append(contentsOf: newItems)
            currentOffset += newItems.count
            hasMore = newItems.count >= pageSize
            
        } catch {
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
    
    func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let imagePath = item.imagePath {
                Task {
                    let url = await StorageManager.shared.imageURL(for: imagePath)
                    if let image = NSImage(contentsOf: url) {
                        pasteboard.writeObjects([image])
                    }
                }
            }
        }
    }
    
    func deleteItem(_ item: ClipItem) async {
        do {
            try await StorageManager.shared.delete(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func togglePinned(_ item: ClipItem) async {
        do {
            try await StorageManager.shared.togglePinned(id: item.id)
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
            try await StorageManager.shared.clearAll(keepPinned: keepPinned)
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
