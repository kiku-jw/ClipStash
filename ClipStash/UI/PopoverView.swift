import SwiftUI

/// Main popover view for clipboard history
struct PopoverView: View {
    @StateObject private var viewModel = PopoverViewModel()
    @State private var selectedItemId: Int64?
    @State private var showingExport = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        viewModel.search()
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Items list
            if viewModel.isLoading && viewModel.items.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.items.isEmpty {
                Spacer()
                Text(viewModel.searchQuery.isEmpty ? "No clipboard history" : "No results")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.items) { item in
                            ClipItemRow(
                                item: item,
                                isSelected: selectedItemId == item.id,
                                onCopy: { viewModel.copyToClipboard(item) },
                                onDelete: { viewModel.delete(item) },
                                onTogglePin: { viewModel.togglePin(item) }
                            )
                            .onTapGesture {
                                selectedItemId = item.id
                            }
                            .onTapGesture(count: 2) {
                                viewModel.copyToClipboard(item)
                            }
                            
                            if item.id != viewModel.items.last?.id {
                                Divider()
                            }
                        }
                        
                        // Load more trigger
                        if viewModel.hasMore {
                            ProgressView()
                                .padding()
                                .onAppear {
                                    viewModel.loadMore()
                                }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            
            Divider()
            
            // Bottom bar
            HStack {
                Button("Export...") {
                    showingExport = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Text("\(viewModel.totalCount) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear") {
                    viewModel.showClearConfirmation = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 350)
        .onAppear {
            viewModel.loadInitial()
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Clear History", isPresented: $viewModel.showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearAll()
            }
        } message: {
            Text("This will delete all non-pinned items. Pinned items will be kept.")
        }
        // Keyboard handling requires macOS 14+, disabled for macOS 13 compatibility
        // TODO: Implement via focusable() + onMoveCommand() for macOS 13
    }
    
    private func selectPrevious() {
        guard !viewModel.items.isEmpty else { return }
        
        if let currentId = selectedItemId,
           let currentIndex = viewModel.items.firstIndex(where: { $0.id == currentId }),
           currentIndex > 0 {
            selectedItemId = viewModel.items[currentIndex - 1].id
        } else {
            selectedItemId = viewModel.items.first?.id
        }
    }
    
    private func selectNext() {
        guard !viewModel.items.isEmpty else { return }
        
        if let currentId = selectedItemId,
           let currentIndex = viewModel.items.firstIndex(where: { $0.id == currentId }),
           currentIndex < viewModel.items.count - 1 {
            selectedItemId = viewModel.items[currentIndex + 1].id
        } else {
            selectedItemId = viewModel.items.first?.id
        }
    }
}

// MARK: - View Model

@MainActor
class PopoverViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var searchQuery: String = ""
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var totalCount = 0
    @Published var showClearConfirmation = false
    
    private let pageSize = 50
    private var currentOffset = 0
    
    func loadInitial() {
        items = []
        currentOffset = 0
        hasMore = true
        loadMore()
        loadTotalCount()
    }
    
    func loadMore() {
        guard !isLoading && hasMore else { return }
        isLoading = true
        
        Task {
            do {
                let newItems: [ClipItem]
                
                if searchQuery.isEmpty {
                    newItems = try await StorageManager.shared.fetchItems(
                        limit: pageSize,
                        offset: currentOffset
                    )
                } else {
                    newItems = try await StorageManager.shared.search(
                        query: searchQuery,
                        limit: pageSize,
                        offset: currentOffset
                    )
                }
                
                await MainActor.run {
                    self.items.append(contentsOf: newItems)
                    self.currentOffset += newItems.count
                    self.hasMore = newItems.count == self.pageSize
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    func search() {
        loadInitial()
    }
    
    func loadTotalCount() {
        Task {
            do {
                let count = try await StorageManager.shared.count()
                await MainActor.run {
                    self.totalCount = count
                }
            } catch {
                // Ignore
            }
        }
    }
    
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
    
    func delete(_ item: ClipItem) {
        Task {
            do {
                try await StorageManager.shared.delete(id: item.id)
                await MainActor.run {
                    self.items.removeAll { $0.id == item.id }
                    self.totalCount -= 1
                }
            } catch {
                // Ignore
            }
        }
    }
    
    func togglePin(_ item: ClipItem) {
        Task {
            do {
                try await StorageManager.shared.togglePinned(id: item.id)
                await MainActor.run {
                    if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[index].pinned.toggle()
                    }
                }
            } catch {
                // Ignore
            }
        }
    }
    
    func clearAll() {
        Task {
            do {
                try await StorageManager.shared.clearAll(keepPinned: true)
                await MainActor.run {
                    self.loadInitial()
                }
            } catch {
                // Ignore
            }
        }
    }
}

#Preview {
    PopoverView()
}
