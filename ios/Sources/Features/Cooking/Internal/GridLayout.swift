import UIKit

/// The table and editor preview use identical cell spans, text metrics, and row heights.
struct RecipeGridGeometry {
    let columnEdges: [CGFloat]
    let rowEdges: [CGFloat]
    let frames: [String: CGRect]
    var size: CGSize { CGSize(width: columnEdges.last!, height: rowEdges.last!) }

    init(cells: [RecipeCell], layout: RecipeTableLayout, theme: AppTheme, density: GridDensity, traits: UITraitCollection, minimumWidth: CGFloat? = nil) {
        let normal = UITraitCollection(preferredContentSizeCategory: .large)
        // Scale usable text width, retaining padding and the selected Compact/Comfort proportions.
        let scale = max(1, max(
            theme.cellFont(size: theme.cellSize, traits: traits).pointSize / theme.cellFont(size: theme.cellSize, traits: normal).pointSize,
            theme.cellFont(size: theme.cellSize - 2, secondary: true, traits: traits).pointSize / theme.cellFont(size: theme.cellSize - 2, secondary: true, traits: normal).pointSize))
        let densityScale: CGFloat = density == .compact ? 0.84 : 1
        let pixelScale = max(1, traits.displayScale)
        func aligned(_ value: CGFloat) -> CGFloat { (value * pixelScale).rounded() / pixelScale }
        let naturalWidths = layout.columnWidths.map { 24 + ($0 * densityScale - 24) * scale }
        let naturalWidth = naturalWidths.reduce(0, +)
        let widthScale = minimumWidth.map { max(1, $0 / naturalWidth) } ?? 1
        columnEdges = naturalWidths.reduce(into: [CGFloat(0)]) {
            $0.append($0.last! + $1 * widthScale)
        }.map(aligned)
        var heights = Array(repeating: CGFloat(density == .compact ? 76 : 92), count: layout.rowCount)
        let byID = Dictionary(uniqueKeysWithValues: cells.map { ($0.id, $0) })
        for placement in layout.placements {
            let width = columnEdges[placement.column + placement.columns] - columnEdges[placement.column]
            let required = GridCellTextLayout.requiredHeight(cell: byID[placement.id]!, theme: theme, width: width, traits: traits)
            let available = heights[placement.row..<(placement.row + placement.rows)].reduce(0, +)
            if required > available { heights[placement.row] += required - available }
        }
        for lane in layout.continuations {
            let width = columnEdges[lane.region.column + lane.region.columns] - columnEdges[lane.region.column]
            let cell = lane.displayCell(targetLabel: byID[lane.targetID]!.label)
            heights[lane.region.row] = max(heights[lane.region.row], GridCellTextLayout.requiredHeight(cell: cell, theme: theme, width: width, traits: traits))
        }
        rowEdges = heights.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }.map(aligned)
        var result: [String: CGRect] = [:]
        for p in layout.occupiedRegions {
            result[p.id] = CGRect(x: columnEdges[p.column], y: rowEdges[p.row], width: columnEdges[p.column + p.columns] - columnEdges[p.column], height: rowEdges[p.row + p.rows] - rowEdges[p.row])
        }
        frames = result
    }
}
