import Foundation

struct SevenSReport: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var sentAt: Date?
    var stund = ""
    var stalle = ""
    var styrka = ""
    var slag = ""
    var sysselsattning = ""
    var symbol = ""
    var sagesman = ""

    var fields: [(String, String)] {
        [("Stund", stund), ("Ställe", stalle), ("Styrka", styrka), ("Slag", slag),
         ("Sysselsättning", sysselsattning), ("Symbol", symbol), ("Sagesman", sagesman)]
    }
    var isEmpty: Bool { fields.allSatisfy { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var isValid: Bool { !isEmpty && fields.allSatisfy { $0.1.count <= 2_000 } }
    var completedCount: Int { fields.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var title: String { stalle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "7S-rapport" : stalle }
    var radioText: String {
        "7S-RAPPORT\n\n" + fields.map { "\($0.0.uppercased()): \($0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ej angivet" : $0.1)" }.joined(separator: "\n\n")
    }
}
