import Foundation

/// Shared formatting utilities
enum Formatters {

    /// Format bytes into human-readable string (B, KB, MB)
    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    /// Format bytes from Int64
    static func formatBytes(_ bytes: Int64) -> String {
        formatBytes(Int(bytes))
    }
}
