import SwiftUI

struct ReportsScreen: View {
    let store: LocalStore
    let location: LocationService
    @State private var recording = false
    @State private var draft: SevenSReport?

    var body: some View {
        NavigationStack {
            Group {
                if store.reports.isEmpty {
                    ContentUnavailableView {
                        Label("Your field notebook", systemImage: "text.document")
                    } description: {
                        Text("Write a report or record it for later.")
                    } actions: {
                        Button("New 7S report", systemImage: "plus") { draft = SevenSReport() }.buttonStyle(
                            PrimaryButtonStyle())
                        Button("Record voice report", systemImage: "mic") { recording = true }.frame(minHeight: 44)
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.reports) { report in
                                NavigationLink {
                                    ReportReader(reportID: report.id, store: store, location: location)
                                } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        HStack {
                                            Label(
                                                report.title,
                                                systemImage: report.recording == nil ? "text.document" : "waveform"
                                            ).font(.headline).lineLimit(1)
                                            Spacer()
                                            Text(report.sentAt == nil ? "DRAFT" : "SENT")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundStyle(report.sentAt == nil ? Theme.muted : Theme.accent)
                                        }
                                        Text(
                                            report.slag.isEmpty
                                                ? "\(report.completedCount) of 7 fields filled" : report.slag
                                        )
                                        .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                                        Text(report.updatedAt, format: .dateTime.day().month().hour().minute())
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                                    }.padding(.vertical, 7)
                                }.listRowBackground(Theme.panel)
                            }
                        } header: {
                            Text("\(store.reports.count) saved locally")
                        }
                    }.scrollContentBackground(.hidden)
                }
            }.background(Theme.background).navigationTitle("7S reports").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { AppMenu() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Record voice report", systemImage: "mic") { recording = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New report", systemImage: "square.and.pencil") { draft = SevenSReport() }
                            .accessibilityIdentifier("new-report")
                    }
                }
                .sheet(item: $draft) { report in ReportEditor(report: report, store: store, location: location) }
                .sheet(isPresented: $recording) {
                    VoiceCaptureSheet(report: SevenSReport(), store: store, location: location) { _ in }
                }
        }
    }
}

struct ReportEditor: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State var report: SevenSReport
    let store: LocalStore
    let location: LocationService
    @State private var recording = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var original: SevenSReport?
    private var dirty: Bool { report != original }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording & notes") {
                    if report.recording != nil {
                        VoiceAttachmentView(report: $report, store: store)
                    } else {
                        Button("Record voice", systemImage: "mic") { recording = true }
                    }
                    if report.recording != nil || report.transcript != nil {
                        TextField(
                            "Transcript / notes",
                            text: Binding(
                                get: { report.transcript ?? "" }, set: { report.transcript = String($0.prefix(30_000)) }
                            ), axis: .vertical
                        )
                        .lineLimit(3...12).autocorrectionDisabled().accessibilityIdentifier("report-transcript")
                        Text("Verify the transcript while filling the seven fields below.").font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                field(
                    "1  Stund", hint: "Observation time, date and time zone", placeholder: "24 sep 2026, 14:35 CEST",
                    text: $report.stund, identifier: "report-stund")
                field(
                    "2  Ställe", hint: "Coordinates, grid reference or place description",
                    placeholder: "Plats eller koordinater", text: $report.stalle, identifier: "report-stalle")
                if let position = location.currentPosition {
                    Section {
                        Button("Use my position as Ställe") { report.stalle = position.coordinate.formatted }
                        Text("\(position.source.rawValue.uppercased()) · \(position.coordinate.formatted)").font(
                            .caption
                        ).foregroundStyle(Theme.muted)
                    }
                }
                field(
                    "3  Styrka", hint: "Number of people, vehicles or units", placeholder: "Antal",
                    text: $report.styrka, identifier: "report-styrka")
                field(
                    "4  Slag", hint: "Observed type or model, if known", placeholder: "Typ av objekt",
                    text: $report.slag, identifier: "report-slag")
                field(
                    "5  Sysselsättning", hint: "Observed activity", placeholder: "Vad händer?",
                    text: $report.sysselsattning, identifier: "report-sysselsattning")
                field(
                    "6  Symbol", hint: "Markings, numbers, colours or insignia", placeholder: "Kännetecken",
                    text: $report.symbol, identifier: "report-symbol")
                field(
                    "7  Sagesman", hint: "Observer or reporting unit", placeholder: "Rapporterat av",
                    text: $report.sagesman, identifier: "report-sagesman")
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("7S-rapport").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                report.updatedAt = Date()
                                // Editing creates new unsent content, so clear a previous sent marker.
                                if dirty { report.sentAt = nil }
                                try store.saveReport(report)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!report.isValid).accessibilityIdentifier("save-report")
                    }
                }
                .onAppear { if original == nil { original = report } }
                .sheet(isPresented: $recording) {
                    VoiceCaptureSheet(report: report, store: store, location: location) { saved in
                        report = saved
                        original = saved
                    }
                }
                .interactiveDismissDisabled(dirty)
                .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible)
            {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
    }

    private func field(_ title: String, hint: String, placeholder: String, text: Binding<String>, identifier: String)
        -> some View
    {
        Section {
            TextField(placeholder, text: text, axis: .vertical).lineLimit(2...6)
                .autocorrectionDisabled().textInputAutocapitalization(.sentences)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
            if text.wrappedValue.count > 2_000 {
                Text("Maximum 2,000 characters per field").font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text(title)
        } footer: {
            Text(hint)
        }
    }
}

struct ReportReader: View {
    let reportID: UUID
    let store: LocalStore
    let location: LocationService
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
                        Label(
                            report.sentAt == nil ? "Saved locally" : "Marked sent",
                            systemImage: report.sentAt == nil ? "internaldrive" : "checkmark.circle"
                        )
                        .font(.caption).foregroundStyle(Theme.accent)
                    }
                    if report.recording != nil {
                        VoiceAttachmentView(
                            report: Binding(
                                get: { self.report ?? report },
                                set: { updated in
                                    do { try store.saveReport(updated) } catch {
                                        self.error = error.localizedDescription
                                    }
                                }), store: store)
                        if let transcript = report.transcript, !transcript.isEmpty {
                            Text("TRANSCRIPT / NOTES").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                            Text(transcript).font(.body).textSelection(.enabled)
                        }
                        Divider()
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
                        } label: {
                            Label("Mark as sent", systemImage: "checkmark")
                        }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("mark-sent")
                    }
                    Text("Read this text using your radio. Marking it as sent only updates this notebook.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Button("Delete report", role: .destructive) { confirmDelete = true }.padding(.top, 8)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(24)
            }
        }.background(Theme.background).navigationTitle("7S-rapport").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { edit = report } } }
            .sheet(item: $edit) { report in ReportEditor(report: report, store: store, location: location) }
            .confirmationDialog(
                "Delete this report from the phone?", isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Delete report", role: .destructive) {
                    do {
                        try store.deleteReport(reportID)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            } message: {
                Text("This cannot be undone.")
            }
    }
}
