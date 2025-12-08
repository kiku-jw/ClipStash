import SwiftUI

/// Sheet for exporting clipboard history
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = Settings.shared
    
    @State private var selectedScope: ExportScopeOption = .last50
    @State private var selectedFormat: ExportService.ExportFormat = .markdown
    @State private var includeImageRefs = false
    @State private var isExporting = false
    @State private var exportResult: ExportService.ExportResult?
    @State private var exportError: String?
    @State private var showWarning = true
    
    enum ExportScopeOption: String, CaseIterable, Identifiable {
        case last50 = "Last 50"
        case last100 = "Last 100"
        case last200 = "Last 200"
        case last500 = "Last 500"
        case today = "Today"
        case lastWeek = "Last 7 Days"
        case pinnedOnly = "Pinned Only"
        
        var id: String { rawValue }
        
        var scope: ExportService.ExportScope {
            switch self {
            case .last50: return .lastN(50)
            case .last100: return .lastN(100)
            case .last200: return .lastN(200)
            case .last500: return .lastN(500)
            case .today: return .today
            case .lastWeek: return .lastWeek
            case .pinnedOnly: return .pinnedOnly
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export History")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if let result = exportResult {
                // Success view
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("Export Complete")
                        .font(.headline)
                    
                    Text("Created \(result.files.count) file(s) with \(result.itemCount) items")
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button("Reveal in Finder") {
                            if let firstFile = result.files.first {
                                Task {
                                    await ExportService.shared.revealInFinder(url: firstFile)
                                }
                            }
                        }
                        
                        Button("Open NotebookLM") {
                            Task {
                                await ExportService.shared.openNotebookLM()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("Done") {
                        dismiss()
                    }
                    .padding(.top)
                }
                .padding(32)
            } else if let error = exportError {
                // Error view
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    
                    Text("Export Failed")
                        .font(.headline)
                    
                    Text(error)
                        .foregroundColor(.secondary)
                    
                    Button("Try Again") {
                        exportError = nil
                    }
                }
                .padding(32)
            } else {
                // Export options
                Form {
                    // Warning
                    if showWarning && !settings.exportWarningShown {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Export may contain sensitive data. Review before sharing.")
                                .font(.caption)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        
                        Button("Don't show again") {
                            settings.exportWarningShown = true
                            showWarning = false
                        }
                        .font(.caption)
                    }
                    
                    // Scope selection
                    Section("What to export") {
                        Picker("Items", selection: $selectedScope) {
                            ForEach(ExportScopeOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // Format selection
                    Section("Format") {
                        Picker("Format", selection: $selectedFormat) {
                            Text("Markdown (.md)").tag(ExportService.ExportFormat.markdown)
                            Text("Plain Text (.txt)").tag(ExportService.ExportFormat.plainText)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Options
                    Section("Options") {
                        Toggle("Include image references", isOn: $includeImageRefs)
                            .help("Copy images to export folder and add references")
                    }
                    
                    // Info
                    Section {
                        Text("Large exports will be automatically split into multiple files (~180KB each) for NotebookLM compatibility.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .formStyle(.grouped)
                .padding()
                
                Divider()
                
                // Actions
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Export") {
                        performExport()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(width: 380, height: exportResult != nil || exportError != nil ? 280 : 420)
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack {
                        ProgressView()
                        Text("Exporting...")
                            .padding(.top, 8)
                    }
                    .padding(24)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func performExport() {
        isExporting = true
        
        Task {
            do {
                let result = try await ExportService.shared.export(
                    scope: selectedScope.scope,
                    format: selectedFormat,
                    includeImageRefs: includeImageRefs
                )
                
                await MainActor.run {
                    self.exportResult = result
                    self.isExporting = false
                }
            } catch {
                await MainActor.run {
                    self.exportError = error.localizedDescription
                    self.isExporting = false
                }
            }
        }
    }
}

#Preview {
    ExportSheet()
}
