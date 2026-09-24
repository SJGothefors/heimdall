import SwiftUI

struct ReportsScreen: View {
    let store: LocalStore
    @State private var draft: SevenSReport?

    var body: some View {
        NavigationStack {
            Group {
                if store.reports.isEmpty {
                    ContentUnavailableView {
                        Label("Your field notebook", systemImage: "text.document")
                    } description: {
                        Text("Save a 7S report, read it over the radio, then remove it when you’re done. Everything stays on this iPhone.")
                    } actions: {
                        Button("New 7S report", systemImage: "plus") { draft = SevenSReport() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.reports) { report in
                                NavigationLink {
                                    ReportReader(reportID: report.id, store: store)
                                } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        HStack {
                                            Text(report.title).font(.headline).lineLimit(1)
                                            Spacer()
                                            Text(report.sentAt == nil ? "DRAFT" : "SENT")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundStyle(report.sentAt == nil ? Theme.muted : Theme.accent)
                                        }
                                        Text(report.slag.isEmpty ? "\(report.completedCount) of 7 fields filled" : report.slag)
                                            .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                                        Text(report.updatedAt, format: .dateTime.day().month().hour().minute())
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                                    }.padding(.vertical, 7)
                                }.listRowBackground(Theme.panel)
                            }
                        } header: { Text("\(store.reports.count) saved locally") }
                    }.scrollContentBackground(.hidden)
                }
            }.background(Theme.background).navigationTitle("7S reports")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New report", systemImage: "square.and.pencil") { draft = SevenSReport() }
                            .accessibilityIdentifier("new-report")
                    }
                }
                .sheet(item: $draft) { report in ReportEditor(report: report, store: store) }
        }
    }
}

struct ReportEditor: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State var report: SevenSReport
    let store: LocalStore
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var original: SevenSReport?
    private var dirty: Bool { report != original }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("\(report.completedCount) / 7 fields", systemImage: "text.document")
                        .foregroundStyle(Theme.accent)
                    if verticalSizeClass != .compact {
                        Text("Keep observations brief. Unfilled fields are shown as “Ej angivet” in the reading view.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                field("1  Stund", hint: "Observation time, date and time zone", placeholder: "24 sep 2026, 14:35 CEST", text: $report.stund, identifier: "report-stund")
                field("2  Ställe", hint: "Coordinates, grid reference or place description", placeholder: "Plats eller koordinater", text: $report.stalle, identifier: "report-stalle")
                field("3  Styrka", hint: "Number of people, vehicles or units", placeholder: "Antal", text: $report.styrka, identifier: "report-styrka")
                field("4  Slag", hint: "Observed type or model, if known", placeholder: "Typ av objekt", text: $report.slag, identifier: "report-slag")
                field("5  Sysselsättning", hint: "Observed activity", placeholder: "Vad händer?", text: $report.sysselsattning, identifier: "report-sysselsattning")
                field("6  Symbol", hint: "Markings, numbers, colours or insignia", placeholder: "Kännetecken", text: $report.symbol, identifier: "report-symbol")
                field("7  Sagesman", hint: "Observer or reporting unit", placeholder: "Rapporterat av", text: $report.sagesman, identifier: "report-sagesman")
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("7S-rapport").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                report.updatedAt = Date()
                                // Editing creates new unsent content, so clear a previous sent marker.
                                if dirty { report.sentAt = nil }
                                try store.saveReport(report); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!report.isValid).accessibilityIdentifier("save-report")
                    }
                }
                .onAppear { if original == nil { original = report } }
                .interactiveDismissDisabled(dirty)
                .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                }
        }
    }

    private func field(_ title: String, hint: String, placeholder: String, text: Binding<String>, identifier: String) -> some View {
        Section {
            TextField(placeholder, text: text, axis: .vertical).lineLimit(2...6)
                .autocorrectionDisabled().textInputAutocapitalization(.sentences)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
            if text.wrappedValue.count > 2_000 { Text("Maximum 2,000 characters per field").font(.caption).foregroundStyle(.red) }
        } header: { Text(title) } footer: { Text(hint) }
    }
}

struct ReportReader: View {
    let reportID: UUID
    let store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var edit: SevenSReport?
    @State private var confirmDelete = false
    @State private var error: String?
    private var report: SevenSReport? { store.reports.first { $0.id == reportID } }

    var body: some View {
        ScrollView {
            if let report {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Eyebrow(text: "READ OVER RADIO")
                        Spacer()
                        Label(report.sentAt == nil ? "Saved locally" : "Marked sent", systemImage: report.sentAt == nil ? "internaldrive" : "checkmark.circle")
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                    Text(report.radioText).font(.system(.title3, design: .monospaced)).lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("radio-text")
                    if let sentAt = report.sentAt {
                        Text("Marked sent \(sentAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    } else {
                        Button {
                            var updated = report
                            updated.sentAt = Date()
                            do { try store.saveReport(updated) } catch { self.error = error.localizedDescription }
                        } label: { Label("Mark as sent", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("mark-sent")
                    }
                    Text("Read this text using your radio. Marking it as sent only updates this notebook.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Button("Delete report", role: .destructive) { confirmDelete = true }.padding(.top, 8)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(24)
            }
        }.background(Theme.background).navigationTitle("7S-rapport").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { edit = report } } }
            .sheet(item: $edit) { report in ReportEditor(report: report, store: store) }
            .confirmationDialog("Delete this report from the phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete report", role: .destructive) {
                    do { try store.deleteReport(reportID); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: { Text("This cannot be undone.") }
    }
}
