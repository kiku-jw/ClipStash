import SwiftUI

/// Export options sheet
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ClipboardViewModel
    
    @State private var scope: ExportScopeOption = .last100
    @State private var format: ExportFormatOption = .markdown
    @State private var includeImages = false
    @State private var isExporting = false
    @State private var result: ExportService.ExportResult?
    @State private var error: String?
    @State private var showWarning = true
    
    enum ExportScopeOption: String, CaseIterable {
        case last50 = "Last 50"
        case last100 = "Last 100"
        case last200 = "Last 200"
        case last500 = "Last 500"
        case today = "Today"
        case lastWeek = "Last 7 Days"
        case pinnedOnly = "Pinned Only"
        
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
    
    enum ExportFormatOption: String, CaseIterable {
        case markdown = "Markdown"
        case plainText = "Plain Text"
        
        var format: ExportService.ExportFormat {
            switch self {
            case .markdown: return .markdown
            case .plainText: return .plainText
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Export Clipboard History")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            if let result = result {
                // Success state
                successView(result)
            } else {
                // Options
                optionsView
            }
        }
        .padding()
        .frame(width: 350)
    }
    
    private var optionsView: some View {
        VStack(spacing: 16) {
            // Warning
            if showWarning && !AppSettings.shared.exportWarningShown {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Export may contain sensitive data")
                        .font(.caption)
                    Spacer()
                    Button("Don't show again") {
                        AppSettings.shared.exportWarningShown = true
                        showWarning = false
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Scope picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Items to export")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $scope) {
                    ForEach(ExportScopeOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            // Format picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Format")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $format) {
                    ForEach(ExportFormatOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            // Include images toggle
            Toggle("Include image references", isOn: $includeImages)
                .toggleStyle(.checkbox)
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Export button
            Button {
                Task { await performExport() }
            } label: {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Export")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
    }
    
    private func successView(_ result: ExportService.ExportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            
            VStack(spacing: 4) {
                Text("Export Complete")
                    .font(.headline)
                
                Text("\(result.files.count) file(s), \(result.itemCount) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(formatBytes(result.totalBytes))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Button("Reveal in Finder") {
                    if let firstFile = result.files.first {
                        Task {
                            await ExportService.shared.revealInFinder(url: firstFile)
                        }
                    }
                }
                .buttonStyle(.bordered)
                
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
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
    
    private func performExport() async {
        isExporting = true
        error = nil
        
        do {
            result = try await ExportService.shared.export(
                scope: scope.scope,
                format: format.format,
                includeImageRefs: includeImages
            )
        } catch {
            self.error = error.localizedDescription
        }
        
        isExporting = false
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

#Preview {
    ExportSheet()
        .environmentObject(ClipboardViewModel())
}
