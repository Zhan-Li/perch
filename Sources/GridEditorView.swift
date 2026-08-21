import AppKit

struct GridSelection: Equatable {
    var x = 0
    var y = 0
    var w = 1
    var h = 1
}

/// Direct manipulation: choose how many divisions the screen has, then drag
/// across the cells a window should fill. Typing four numbers into a JSON file
/// describes the same thing, but nobody can picture it while they type.
final class GridEditorView: NSView {

    var columns = 2 {
        didSet { clampSelection(); needsDisplay = true }
    }
    var rows = 2 {
        didSet { clampSelection(); needsDisplay = true }
    }
    var selection = GridSelection() {
        didSet { needsDisplay = true }
    }

    var onSelectionChanged: ((GridSelection) -> Void)?

    /// Where the current drag started, in cell coordinates.
    private var anchor: (column: Int, row: Int)?

    // Cell rows count downwards, matching the zone model and Quartz space.
    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor(white: 0.5, alpha: 0.10).setFill()
        outline.fill()

        let cellWidth = bounds.width / CGFloat(columns)
        let cellHeight = bounds.height / CGFloat(rows)

        let selected = NSRect(
            x: CGFloat(selection.x) * cellWidth,
            y: CGFloat(selection.y) * cellHeight,
            width: CGFloat(selection.w) * cellWidth,
            height: CGFloat(selection.h) * cellHeight
        )
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: selected.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4).fill()

        let lines = NSBezierPath()
        lines.lineWidth = 1
        for column in 1..<max(1, columns) {
            let x = CGFloat(column) * cellWidth
            lines.move(to: NSPoint(x: x, y: 0))
            lines.line(to: NSPoint(x: x, y: bounds.height))
        }
        for row in 1..<max(1, rows) {
            let y = CGFloat(row) * cellHeight
            lines.move(to: NSPoint(x: 0, y: y))
            lines.line(to: NSPoint(x: bounds.width, y: y))
        }
        NSColor.separatorColor.setStroke()
        lines.stroke()

        outline.lineWidth = 1
        NSColor.separatorColor.setStroke()
        outline.stroke()
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        let cell = self.cell(at: convert(event.locationInWindow, from: nil))
        anchor = cell
        apply(from: cell, to: cell)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        apply(from: anchor, to: cell(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        anchor = nil
    }

    private func cell(at point: NSPoint) -> (column: Int, row: Int) {
        let cellWidth = bounds.width / CGFloat(columns)
        let cellHeight = bounds.height / CGFloat(rows)
        let column = min(columns - 1, max(0, Int(point.x / cellWidth)))
        let row = min(rows - 1, max(0, Int(point.y / cellHeight)))
        return (column, row)
    }

    private func apply(from start: (column: Int, row: Int), to end: (column: Int, row: Int)) {
        let new = GridSelection(
            x: min(start.column, end.column),
            y: min(start.row, end.row),
            w: abs(end.column - start.column) + 1,
            h: abs(end.row - start.row) + 1
        )
        guard new != selection else { return }
        selection = new
        onSelectionChanged?(new)
    }

    /// Keeps the selection inside the grid after the divisions shrink.
    private func clampSelection() {
        var next = selection
        next.x = min(next.x, columns - 1)
        next.y = min(next.y, rows - 1)
        next.w = min(next.w, columns - next.x)
        next.h = min(next.h, rows - next.y)
        if next != selection {
            selection = next
            onSelectionChanged?(next)
        }
    }
}
