import AppKit
import SwiftUI

/// Searchable list of recent dictations. Click Copy to put one back on the clipboard.
struct HistoryView: View {
    @ObservedObject var history: DictationHistory
    @State private var query = ""
    @State private var copied: UUID?

    private var filtered: [DictationHistory.Entry] {
        query.isEmpty ? history.entries : history.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search dictations", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if filtered.isEmpty {
                Spacer()
                Text(history.entries.isEmpty ? "Nothing dictated yet." : "No matches.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text).lineLimit(3).textSelection(.enabled)
                            Text([entry.app.map(EditWatcher.appName), entry.date.formatted(.relative(presentation: .named))]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(copied == entry.id ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            copied = entry.id
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(width: 520, height: 560)
    }
}
