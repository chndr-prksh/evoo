import AppKit
import EvooCore
import SwiftUI

/// Recent dictations and voice notes, searchable by words or meaning ("what did I say about the invoice").
@MainActor
final class HistoryQuery: ObservableObject {
    static let shared = HistoryQuery()
    @Published var text = ""
    @Published var showNotes = false
}

struct HistoryView: View {
    @ObservedObject var history: DictationHistory
    @ObservedObject var notes: DictationHistory
    @ObservedObject var query: HistoryQuery
    @State private var copied: UUID?

    private var source: DictationHistory { query.showNotes ? notes : history }

    private var filtered: [DictationHistory.Entry] {
        let entries = source.entries
        guard !query.text.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        return SemanticSearch.rank(query.text, in: entries.map(\.text)).map { entries[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $query.showNotes) {
                Text("Dictations").tag(false)
                Text("Notes").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 12)
            TextField("Search by words or meaning", text: $query.text)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if filtered.isEmpty {
                Spacer()
                Text(source.entries.isEmpty
                    ? (query.showNotes ? "No notes yet — say “note: …”." : "Nothing dictated yet.")
                    : "No matches.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text).lineLimit(4).textSelection(.enabled)
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
        .frame(width: 540, height: 580)
    }
}
