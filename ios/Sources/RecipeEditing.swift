import Foundation

enum CellEditField: String, CaseIterable {
    case label, quantity, minimum = "min", maximum = "max", unit, cue
}

struct CellEditIssue: LocalizedError, Equatable {
    let field: CellEditField
    let message: String
    var errorDescription: String? { message }
}

/// Raw duration inputs remain editable while errors are associated with their fields.
struct DurationInput {
    var minimum: String
    var maximum: String
    var unit: String
    var approximate: Bool
    private var first: String { minimum.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var last: String { maximum.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    var value: EditedDuration? {
        guard !first.isEmpty, let start = number(first), let end = last.isEmpty ? start : number(last) else { return nil }
        return EditedDuration(min: start, max: end, unit: unit, approximate: approximate)
    }
    var issues: [CellEditIssue] {
        if first.isEmpty && last.isEmpty { return [] }
        var result: [CellEditIssue] = []
        for (field, text) in [(CellEditField.minimum, first), (.maximum, last)] {
            if text.isEmpty {
                if field == .minimum { result.append(.init(field: field, message: "Enter a start time, or clear both times.")) }
            } else if let number = number(text) {
                if !number.isFinite || number < 0 { result.append(.init(field: field, message: "Use zero or a positive time.")) }
            } else { result.append(.init(field: field, message: "Enter a valid number.")) }
        }
        if let value {
            result += value.issues.filter { issue in !result.contains { $0.field == issue.field } }
        }
        return result
    }
}

struct EditedDuration: Codable, Equatable {
    var min: Double
    var max: Double
    var unit: String
    var approximate: Bool
    var issues: [CellEditIssue] {
        var result: [CellEditIssue] = []
        if !min.isFinite || min < 0 { result.append(.init(field: .minimum, message: "Use zero or a positive time.")) }
        if !max.isFinite || max < 0 { result.append(.init(field: .maximum, message: "Use zero or a positive time.")) }
        else if min.isFinite && min >= 0 && max < min { result.append(.init(field: .maximum, message: "Must be at least the start time.")) }
        if !["sec", "min", "h"].contains(unit) { result.append(.init(field: .unit, message: "Choose seconds, minutes, or hours.")) }
        return result
    }
    var display: String {
        let first = min.formatted(.number.precision(.fractionLength(0...1)))
        let last = max.formatted(.number.precision(.fractionLength(0...1)))
        return (approximate ? "≈" : "") + (min == max ? first : "\(first)–\(last)") + " \(unit)"
    }
}

struct CellContent: Codable, Equatable {
    var label: String
    var quantity: String
    var duration: EditedDuration?
    var cue: String
    var instruction: String

    var issues: [CellEditIssue] {
        var result: [CellEditIssue] = []
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { result.append(.init(field: .label, message: "Enter an ingredient or action name.")) }
        else if name.contains(where: { $0.isNewline }) { result.append(.init(field: .label, message: "Use a short phrase. Put paragraphs in the full explanation.")) }
        for (field, text) in [(CellEditField.quantity, quantity), (.cue, cue)] where text.contains(where: { $0.isNewline }) {
            result.append(.init(field: field, message: "Use a short phrase. Put paragraphs in the full explanation."))
        }
        if let duration { result += duration.issues }
        return result
    }
    func validated() throws -> CellContent {
        if let issue = issues.first { throw issue }
        var value = self
        value.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    func applying(to cell: RecipeCell) -> RecipeCell {
        RecipeCell(id: cell.id, label: label, amount: cell.isIngredient ? (quantity.isEmpty ? nil : quantity) : duration?.display,
                   cue: cue, instruction: instruction, isIngredient: cell.isIngredient, dependencies: cell.dependencies,
                   inputReferences: cell.inputReferences)
    }
}

struct RecipeEdits: Codable {
    var version = 1
    var recipeID: String
    var cells: [String: CellContent] = [:]
}
