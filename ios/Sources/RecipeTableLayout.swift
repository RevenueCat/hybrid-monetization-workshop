import Foundation

struct CellPlacement: Equatable {
    let id: String
    var row: Int
    let column: Int
    var rows = 1
    var columns = 1
}

struct RecipeInputReference: Equatable {
    enum Kind: Equatable { case ingredient, ordering }
    let sourceID: String
    let targetID: String
    let kind: Kind
    let allocation: String?
    let optional: Bool

    func text(sourceLabel: String) -> String {
        let label = kind == .ingredient ? "+ \(sourceLabel)" : "After \(sourceLabel)"
        return ([label, allocation, optional ? "Optional" : nil].compactMap { $0 }).joined(separator: " · ")
    }
}

struct RecipeContinuation: Equatable {
    struct Material: Equatable {
        let outputID: String
        let name: String
        let allocation: String?
        let optional: Bool
        var text: String { ([name, allocation, optional ? "Optional" : nil].compactMap { $0 }).joined(separator: " · ") }
    }
    let sourceID: String
    let targetID: String
    let materials: [Material]
    var region: CellPlacement
    var id: String { region.id }
    var text: String { materials.map(\.text).joined(separator: "\n") }
    func displayCell(targetLabel: String) -> RecipeCell {
        RecipeCell(id: id, label: materials.map(\.name).joined(separator: " · "), amount: nil,
                   cue: materials.map { [$0.allocation, $0.optional ? "Optional" : nil].compactMap { $0 }.joined(separator: " · ") }.filter { !$0.isEmpty }.joined(separator: " · "), instruction: "",
                   isIngredient: false, dependencies: [])
    }
}

private struct GeneratedLayoutBlock {
    var placements: [CellPlacement]
    let rootID: String
    let width: Int
    let height: Int
}

/// Derived presentation only. Semantic cells retain exactly one progress identity.
struct RecipeTableLayout {
    let placements: [CellPlacement]
    let columnWidths: [CGFloat]
    var fillsAvailableWidth = false
    var references: [RecipeInputReference] = []
    var continuations: [RecipeContinuation] = []
    var fillers: [CellPlacement] = []
    var order: [String] { placements.map(\.id) }
    var readingOrder: [String] {
        placements.sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            if $0.column != $1.column { return $0.column < $1.column }
            return $0.id < $1.id
        }.map(\.id)
    }
    var occupiedRegions: [CellPlacement] { placements + continuations.map(\.region) + fillers }
    var rowCount: Int { occupiedRegions.map { $0.row + $0.rows }.max() ?? 0 }

    private static func materials(from sourceID: String, to targetID: String, in graph: RecipeGraph) -> [RecipeContinuation.Material] {
        guard let source = graph.recipe.steps.first(where: { $0.id == sourceID }),
              let target = graph.recipe.steps.first(where: { $0.id == targetID }) else { return [] }
        return target.inputs.compactMap { input in
            guard let output = source.outputs.first(where: { $0.id == input.output }) else { return nil }
            return .init(outputID: output.id, name: output.name, allocation: input.allocation, optional: input.optional ?? false)
        }
    }

    private static func reference(from sourceID: String, to targetID: String, in graph: RecipeGraph) -> RecipeInputReference {
        let ingredient = graph.cells[sourceID]!.isIngredient
        let input = graph.recipe.steps.first { $0.id == targetID }?.inputs.first { $0.ingredient == sourceID }
        return .init(sourceID: sourceID, targetID: targetID, kind: ingredient ? .ingredient : .ordering,
                     allocation: input?.allocation, optional: input?.optional ?? false)
    }

    static func generated(for graph: RecipeGraph, columnWidth: CGFloat = 122) throws -> RecipeTableLayout {
        var dependents: [String: [String]] = [:]
        for targetID in graph.order {
            for sourceID in graph.cells[targetID]!.dependencies {
                dependents[sourceID, default: []].append(targetID)
            }
        }
        var references: [RecipeInputReference] = []
        var bypasses: [(source: String, target: String)] = []
        for targetID in graph.order {
            for sourceID in graph.cells[targetID]!.dependencies where dependents[sourceID]?.first != targetID {
                if materials(from: sourceID, to: targetID, in: graph).isEmpty {
                    references.append(reference(from: sourceID, to: targetID, in: graph))
                } else { bypasses.append((sourceID, targetID)) }
            }
        }
        let sharedPreparations = Set(bypasses.map(\.source))
        func build(_ id: String) -> GeneratedLayoutBlock {
            let dependencies = graph.cells[id]!.dependencies.filter { dependents[$0]?.first == id }
            guard !dependencies.isEmpty else {
                return GeneratedLayoutBlock(placements: [.init(id: id, row: 0, column: 0)], rootID: id, width: 1, height: 1)
            }
            // Put a branch carrying a held preparation below other inputs. This
            // leaves a continuous neutral lane below its intervening consumers.
            var blocks = dependencies.map(build).enumerated().sorted { lhs, rhs in
                let leftCarries = lhs.element.placements.contains { sharedPreparations.contains($0.id) }
                let rightCarries = rhs.element.placements.contains { sharedPreparations.contains($0.id) }
                if !bypasses.contains(where: { $0.target == id }), leftCarries != rightCarries { return !leftCarries }
                let leftIngredient = graph.cells[lhs.element.rootID]!.isIngredient
                let rightIngredient = graph.cells[rhs.element.rootID]!.isIngredient
                // Ingredients introduced at this merge follow the branches
                // that prepare its other inputs, rather than jumping above them.
                if leftIngredient != rightIngredient { return !leftIngredient }
                return lhs.offset < rhs.offset
            }.map(\.element)
            let targetColumn = blocks.map(\.width).max()!
            var placements: [CellPlacement] = []
            var nextRow = 0
            for index in blocks.indices {
                let rootIndex = blocks[index].placements.firstIndex { $0.id == blocks[index].rootID }!
                blocks[index].placements[rootIndex].columns += targetColumn - blocks[index].width
                placements += blocks[index].placements.map {
                    CellPlacement(id: $0.id, row: $0.row + nextRow, column: $0.column, rows: $0.rows, columns: $0.columns)
                }
                nextRow += blocks[index].height
            }
            placements.append(.init(id: id, row: 0, column: targetColumn, rows: nextRow))
            return GeneratedLayoutBlock(placements: placements, rootID: id, width: targetColumn + 1, height: nextRow)
        }
        let sinks = graph.order.filter { dependents[$0, default: []].isEmpty }
        var blocks = sinks.map(build)
        guard let totalColumns = blocks.map(\.width).max() else { throw RecipeError.invalid("Recipe table requires at least one cell.") }
        var placements: [CellPlacement] = []
        var nextRow = 0
        for index in blocks.indices {
            let rootIndex = blocks[index].placements.firstIndex { $0.id == blocks[index].rootID }!
            blocks[index].placements[rootIndex].columns += totalColumns - blocks[index].width
            placements += blocks[index].placements.map {
                CellPlacement(id: $0.id, row: $0.row + nextRow, column: $0.column, rows: $0.rows, columns: $0.columns)
            }
            nextRow += blocks[index].height
        }

        var continuations: [RecipeContinuation] = []
        for bypass in bypasses {
            let source = placements.first { $0.id == bypass.source }!
            let target = placements.first { $0.id == bypass.target }!
            var laneRow = source.row + source.rows
            let laneColumn = source.column + source.columns
            // A held portion rejoins a later consumer on the primary route.
            // Unsupported crossings are rejected rather than dropping an edge.
            var ancestors = Set<String>()
            var next = dependents[bypass.source]?.first
            while let id = next, ancestors.insert(id).inserted { next = dependents[id]?.first }
            guard ancestors.contains(bypass.target), target.column > laneColumn else {
                throw RecipeError.invalid("Unsupported continuation route: \(bypass.source) → \(bypass.target).")
            }
            var intervening: [String] = []
            next = dependents[bypass.source]?.first
            while let id = next, id != bypass.target {
                intervening.append(id)
                next = dependents[id]?.first
            }
            let canShareSourceRows = source.rows > 1 && intervening.allSatisfy { id in
                let region = placements.first { $0.id == id }!
                return region.row + region.rows == laneRow && region.rows > 1
            }
            if canShareSourceRows {
                // Split the producer's existing vertical extent between the main
                // route and the held output; no extra row or upstream gap.
                laneRow -= 1
                for index in placements.indices where intervening.contains(placements[index].id) {
                    placements[index].rows -= 1
                }
            } else {
                var expand = Set([bypass.source, bypass.target])
                next = dependents[bypass.target]?.first
                while let id = next, expand.insert(id).inserted { next = dependents[id]?.first }
                // Stretch the bottom input path together with the producer.
                func expandInputs(_ id: String) {
                    for input in graph.cells[id]!.dependencies {
                        guard let region = placements.first(where: { $0.id == input }),
                              region.row + region.rows == laneRow else { continue }
                        if expand.insert(input).inserted { expandInputs(input) }
                    }
                }
                expandInputs(bypass.source)
                for index in placements.indices {
                    if placements[index].row >= laneRow { placements[index].row += 1 }
                    else if expand.contains(placements[index].id) || placements[index].row + placements[index].rows > laneRow {
                        placements[index].rows += 1
                    }
                }
                for index in continuations.indices where continuations[index].region.row >= laneRow {
                    continuations[index].region.row += 1
                }
            }
            continuations.append(.init(sourceID: bypass.source, targetID: bypass.target,
                                       materials: materials(from: bypass.source, to: bypass.target, in: graph),
                                       region: .init(id: "continuation:\(bypass.source):\(bypass.target)", row: laneRow, column: laneColumn,
                                                     columns: target.column - laneColumn)))
        }
        // Empty space before a split is neutral, never an extra ingredient or action.
        var occupied = Set<String>()
        for region in placements + continuations.map(\.region) {
            for row in region.row..<(region.row + region.rows) {
                for column in region.column..<(region.column + region.columns) { occupied.insert("\(row),\(column)") }
            }
        }
        let rowCount = placements.map { $0.row + $0.rows }.max() ?? 0
        var fillers: [CellPlacement] = []
        for row in 0..<rowCount {
            var column = 0
            while column < totalColumns {
                if occupied.contains("\(row),\(column)") { column += 1; continue }
                let start = column
                while column < totalColumns && !occupied.contains("\(row),\(column)") { column += 1 }
                fillers.append(.init(id: "filler:\(row):\(start)", row: row, column: start, columns: column - start))
            }
        }
        let layout = RecipeTableLayout(placements: placements, columnWidths: Array(repeating: columnWidth, count: totalColumns),
                                       references: references, continuations: continuations, fillers: fillers)
        try layout.validate(for: graph)
        return layout
    }

    /// Every direct cell dependency has one representation: contact, a source
    /// reference in its consumer, or a labelled material continuation lane.
    func validate(for graph: RecipeGraph) throws {
        guard !columnWidths.isEmpty, columnWidths.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw RecipeError.invalid("Recipe grid column widths must be finite and positive.")
        }
        guard Set(placements.map(\.id)).count == placements.count, Set(placements.map(\.id)) == Set(graph.order) else {
            throw RecipeError.invalid("Recipe identifiers and grid placements must match exactly.")
        }
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        guard Set(occupiedRegions.map(\.id)).count == occupiedRegions.count else { throw RecipeError.invalid("Duplicate layout region.") }
        var slots = Set<String>()
        for region in occupiedRegions {
            guard region.row >= 0, region.column >= 0, region.rows > 0, region.columns > 0,
                  region.column + region.columns <= columnWidths.count else { throw RecipeError.invalid("Recipe grid placement is outside its declared bounds: \(region.id)") }
            for row in region.row..<(region.row + region.rows) {
                for column in region.column..<(region.column + region.columns) {
                    guard slots.insert("\(row),\(column)").inserted else { throw RecipeError.invalid("Recipe grid placements overlap at row \(row), column \(column).") }
                }
            }
        }
        guard slots.count == rowCount * columnWidths.count else { throw RecipeError.invalid("Recipe grid contains uncovered slots.") }
        var represented: [String: Int] = [:]
        func add(_ source: String, _ target: String) throws {
            guard graph.cells[target]?.dependencies.contains(source) == true else { throw RecipeError.invalid("Recipe grid connections do not match \(target): unexpected \(source).") }
            represented["\(source)>\(target)", default: 0] += 1
        }
        for targetID in graph.order {
            let target = byID[targetID]!
            for sourceID in graph.cells[targetID]!.dependencies {
                let source = byID[sourceID]!
                guard source.column + source.columns <= target.column else { throw RecipeError.invalid("Recipe grid dependency must progress left-to-right: \(sourceID) → \(targetID).") }
            }
            for source in placements where source.id != targetID && source.column + source.columns == target.column && source.row < target.row + target.rows && target.row < source.row + source.rows {
                try add(source.id, targetID)
            }
        }
        for reference in references {
            try add(reference.sourceID, reference.targetID)
            guard Self.materials(from: reference.sourceID, to: reference.targetID, in: graph).isEmpty,
                  reference == Self.reference(from: reference.sourceID, to: reference.targetID, in: graph) else { throw RecipeError.invalid("Invalid ingredient or ordering reference.") }
        }
        for lane in continuations {
            try add(lane.sourceID, lane.targetID)
            let source = byID[lane.sourceID]!, target = byID[lane.targetID]!
            guard !lane.materials.isEmpty, lane.materials == Self.materials(from: lane.sourceID, to: lane.targetID, in: graph),
                  lane.region.rows == 1, lane.region.column == source.column + source.columns,
                  lane.region.column + lane.region.columns == target.column,
                  lane.region.row >= source.row, lane.region.row < source.row + source.rows,
                  lane.region.row >= target.row, lane.region.row < target.row + target.rows else { throw RecipeError.invalid("Invalid material continuation: \(lane.sourceID) → \(lane.targetID).") }
        }
        for target in graph.order {
            for source in graph.cells[target]!.dependencies {
                guard represented["\(source)>\(target)"] == 1 else { throw RecipeError.invalid("Recipe grid requires exactly one connection: \(source) → \(target).") }
            }
        }
    }
}
