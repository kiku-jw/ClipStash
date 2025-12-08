import SwiftUI
import Combine

/// Filter for clipboard content types
enum ClipFilter: String, CaseIterable {
    case all = "All"
    case text = "Text"
    case images = "Images"
}

/// Main popover view showing clipboard history
struct PopoverView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @EnvironmentObject var settings: AppSettings
    
    @State private var showClearConfirmation = false
    @State private var hoveredItemId: Int64?
    @State private var selectedFilter: ClipFilter = .all
    @State private var selectedApp: String = "all"
    @State private var availableApps: [String] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var detailItem: ClipItem?
    @FocusState private var isSearchFocused: Bool
    
    private var filteredItems: [ClipItem] {
        var items = viewModel.items
        
        // Filter by type
        switch selectedFilter {
        case .all: break
        case .text:
            items = items.filter { $0.type == .text }
        case .images:
            items = items.filter { $0.type == .image }
        }
        
        // Filter by app
        if selectedApp != "all" {
            items = items.filter { $0.sourceBundleId == selectedApp }
        }
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and filter
            headerView
            
            Divider()
            
            // Items list
            if filteredItems.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                itemsList
            }
            
            // Loading indicator
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: 400, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Task { 
                await viewModel.loadInitial()
                await loadAvailableApps()
            }
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.copySelected()
            return .handled
        }
        .onKeyPress(.escape) {
            if !viewModel.searchQuery.isEmpty {
                viewModel.searchQuery = ""
                triggerSearch()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            Task { await viewModel.deleteSelected() }
            return .handled
        }
        .confirmationDialog("Clear History", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                Task { await viewModel.clearHistory(keepPinned: false) }
            }
            Button("Keep Pinned Items") {
                Task { await viewModel.clearHistory(keepPinned: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(item: $detailItem) { item in
            ItemDetailView(item: item)
        }
    }
    
    private func loadAvailableApps() async {
        do {
            availableApps = try await StorageManager.shared.getUniqueApps()
        } catch {
            availableApps = []
        }
    }
    
    private func triggerSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 8) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                TextField("Search clipboard...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        triggerSearch()
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        triggerSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Filter row
            HStack(spacing: 8) {
                // Type filter
                Picker("", selection: $selectedFilter) {
                    ForEach(ClipFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                
                // App filter
                Menu {
                    Button("All Apps") {
                        selectedApp = "all"
                    }
                    if !availableApps.isEmpty {
                        Divider()
                        ForEach(availableApps, id: \.self) { app in
                            Button(appDisplayName(for: app)) {
                                selectedApp = app
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 10))
                        Text(selectedApp == "all" ? "Apps" : appDisplayName(for: selectedApp))
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedApp != "all" ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Clear button
                Button {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.8))
                .help("Clear History")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private func appDisplayName(for bundleId: String) -> String {
        let components = bundleId.split(separator: ".")
        if let last = components.last {
            let name = String(last)
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return bundleId
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .images ? "photo.on.rectangle" : "clipboard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 4) {
                Text(emptyStateTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(emptyStateSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateTitle: String {
        if !viewModel.searchQuery.isEmpty {
            return "No results"
        }
        if selectedApp != "all" {
            return "No items from this app"
        }
        switch selectedFilter {
        case .all: return "No clipboard history"
        case .text: return "No text items"
        case .images: return "No images"
        }
    }
    
    private var emptyStateSubtitle: String {
        if !viewModel.searchQuery.isEmpty {
            return "Try a different search term"
        }
        if selectedApp != "all" {
            return "Copy something from \(appDisplayName(for: selectedApp))"
        }
        switch selectedFilter {
        case .all: return "Copied items will appear here"
        case .text: return "Copy text to see it here"
        case .images: return "Copy images to see them here"
        }
    }
    
    // MARK: - Items List
    
    private var itemsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredItems) { item in
                        ClipItemRow(item: item)
                            .id(item.id)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(backgroundColor(for: item))
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedItemId = item.id
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    detailItem = item
                                }
                            )
                            .onHover { isHovered in
                                hoveredItemId = isHovered ? item.id : nil
                            }
                            .contextMenu {
                                Button {
                                    viewModel.copyToClipboard(item)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                
                                Button {
                                    Task { await viewModel.togglePinned(item) }
                                } label: {
                                    Label(item.pinned ? "Unpin" : "Pin", 
                                          systemImage: item.pinned ? "pin.slash" : "pin")
                                }
                                
                                if let app = item.sourceBundleId {
                                    Button {
                                        selectedApp = app
                                    } label: {
                                        Label("Filter by \(appDisplayName(for: app))", systemImage: "line.3.horizontal.decrease.circle")
                                    }
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(item) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .onAppear {
                                if item.id == viewModel.items.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedItemId) { oldId, newId in
                if let newId = newId {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }
    
    private func backgroundColor(for item: ClipItem) -> Color {
        if viewModel.selectedItemId == item.id {
            return Color.blue.opacity(0.15)
        } else if hoveredItemId == item.id {
            return Color(NSColor.controlBackgroundColor).opacity(0.5)
        } else {
            return Color.clear
        }
    }
}

#Preview {
    PopoverView()
        .environmentObject(ClipboardViewModel())
        .environmentObject(AppSettings.shared)
}
