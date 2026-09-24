import SwiftUI

struct AnnotationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var annotation: MapAnnotation
    let store: LocalStore
    @State private var error: String?
    @State private var confirmDelete = false
    private var exists: Bool { store.annotations.contains { $0.id == annotation.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Annotation") {
                    TextField("Name", text: $annotation.title).accessibilityIdentifier("annotation-name")
                    Picker("Layer", selection: $annotation.layer) {
                        ForEach(TacticalLayer.allCases) { layer in Text("\(layer.rawValue) · \(layer.title)").tag(layer) }
                    }
                    TextField("Notes", text: $annotation.notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Position · WGS 84") {
                    if let coordinate = annotation.coordinates.first { Text(coordinate.formatted).font(.system(.footnote, design: .monospaced)) }
                    LabeledContent("Geometry", value: annotation.kind.rawValue.capitalized)
                    if annotation.kind != .point { LabeledContent("Vertices", value: "\(annotation.coordinates.count)") }
                }
                if exists { Section { Button("Delete annotation", role: .destructive) { confirmDelete = true } } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle(exists ? "Edit annotation" : "New annotation").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                if annotation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { annotation.title = "\(annotation.layer.rawValue) \(annotation.kind.rawValue)" }
                                try store.save(annotation); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!annotation.isValid)
                    }
                }
                .confirmationDialog("Delete this annotation?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        do { try store.deleteAnnotation(annotation.id); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
}

struct LayerSheet: View {
    let store: LocalStore
    @Binding var visible: Set<TacticalLayer>
    @Binding var active: TacticalLayer
    let select: (MapAnnotation) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(TacticalLayer.allCases) { layer in
                    Section {
                        Toggle(isOn: Binding(get: { visible.contains(layer) }, set: { if $0 { visible.insert(layer) } else { visible.remove(layer) } })) {
                            Label(layer.title, systemImage: layer.symbol).foregroundStyle(layer.color)
                        }.tint(layer.color)
                        let items = store.annotations.filter { $0.layer == layer }
                        if items.isEmpty { Text("No annotations yet").font(.caption).foregroundStyle(Theme.muted) }
                        ForEach(items) { annotation in
                            Button { select(annotation) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(annotation.title).foregroundStyle(.white)
                                        Text(annotation.kind.rawValue.capitalized).font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    } header: { Text(layer.rawValue) }
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("Layers").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
