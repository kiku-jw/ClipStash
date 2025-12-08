import SwiftUI

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
    
    @State private var showExportSheet = false
    @State private var showClearConfirmation = false
    @State private var hoveredItemId: Int64?
    @State private var selectedFilter: ClipFilter = .all
    @FocusState private var isSearchFocused: Bool
    
    private var filteredItems: [ClipItem] {
        switch selectedFilter {
        case .all:
            return viewModel.items
        case .text:
            return viewModel.items.filter { $0.type == .text }
        case .images:
            return viewModel.items.filter { $0.type == .image }
        }
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
        .frame(width: 380, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Task { await viewModel.loadInitial() }
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
                Task { await viewModel.search() }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            Task { await viewModel.deleteSelected() }
            return .handled
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet()
                .environmentObject(viewModel)
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
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        Task { await viewModel.search() }
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
            
            // Filter tabs + actions
            HStack(spacing: 8) {
                // Filter picker
                Picker("", selection: $selectedFilter) {
                    ForEach(ClipFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                
                Spacer()
                
                // Export button
                Button {
                    showExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .help("Export")
                
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
                                // Single tap - select immediately
                                viewModel.selectedItemId = item.id
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    // Double tap - copy
                                    viewModel.copyToClipboard(item)
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
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(item) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .onAppear {
                                // Load more when reaching end
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
