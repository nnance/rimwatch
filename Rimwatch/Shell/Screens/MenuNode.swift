import GameCore
import SpriteKit
import UIKit

/// Draws any `Menu` (title, pause, options, high scores, game over) and turns touches on it into
/// choices. It holds no game logic: the menu's contents, enabled states and selection come from
/// `FrontEnd`, which a gamepad can drive the same way.
///
/// Two layouts, picked from the current size:
/// - landscape (the open inner display): heading on the left half, items on the right half, each
///   kept clear of the crease band down the middle;
/// - portrait (the closed outer display): heading at the top, items stacked below.
///
/// The title adds the game's emblem above its heading, and under the heading shows the details
/// of the highlighted item (a mode's summary and best score).
@MainActor
final class MenuNode: SKNode {
    struct Choice: Equatable {
        let index: Int
        /// For an option row: -1 for its down arrow, +1 for its up arrow, 0 for anywhere else on
        /// the row (select it, change nothing). For any other item, +1 (activate it).
        let step: Int
    }

    private let shellStyle: ShellStyle
    private var menu: Menu?
    private var geometryKey = ""
    private var sceneSize: CGSize = .zero
    /// Hit rectangles of the items, in scene coordinates.
    private var itemFrames: [CGRect] = []
    private var itemNodes: [SKNode] = []
    /// The down-arrow hit area of each adjustable item.
    private var decrementFrames: [Int: CGRect] = [:]
    /// The up-arrow hit area of each adjustable item.
    private var incrementFrames: [Int: CGRect] = [:]
    private var pressed: (touch: ObjectIdentifier, index: Int)?

    private var accent: RGB { shellStyle.text }
    private var headingColor: RGB { shellStyle.heading }

    init(style: ShellStyle) {
        self.shellStyle = style
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    var isShowing: Bool { menu != nil }

    /// Whether item `index` of the menu on show is an option with arrows.
    func isAdjustable(_ index: Int) -> Bool {
        guard let menu, menu.items.indices.contains(index) else { return false }
        return menu.items[index].isAdjustable
    }

    /// Shows `menu`, rebuilding only when it or the geometry changed.
    func show(_ menu: Menu, size: CGSize, safeArea: UIEdgeInsets, keepClear: ClosedRange<CGFloat>?) {
        let geometry = "\(size.width)x\(size.height)|\(safeArea)|\(keepClear.map { "\($0)" } ?? "-")"
        guard menu != self.menu || geometry != geometryKey else { return }
        let sameScreen = self.menu?.kind == menu.kind && geometry == geometryKey
        self.menu = menu
        geometryKey = geometry
        sceneSize = size
        if !sameScreen { pressed = nil }
        rebuild(menu, size: size, safeArea: safeArea, keepClear: keepClear)
    }

    func hide() {
        guard menu != nil else { return }
        menu = nil
        geometryKey = ""
        pressed = nil
        removeAllChildren()
        itemFrames = []
        itemNodes = []
        decrementFrames = [:]
        incrementFrames = [:]
    }

    // MARK: Touches

    func touchBegan(_ touch: UITouch) {
        guard pressed == nil, let menu else { return }
        let p = touch.location(in: self)
        if menu.kind == .gameOver {
            pressed = (ObjectIdentifier(touch), 0)
            return
        }
        guard let index = itemFrames.firstIndex(where: { $0.contains(p) }), menu.items[index].isEnabled else { return }
        pressed = (ObjectIdentifier(touch), index)
        itemNodes[index].setScale(0.97)
        itemNodes[index].alpha = 0.75
    }

    /// Returns a choice when a touch lifts on the item it went down on.
    func touchEnded(_ touch: UITouch, cancelled: Bool = false) -> Choice? {
        guard let pressed, pressed.touch == ObjectIdentifier(touch), let menu else { return nil }
        self.pressed = nil
        if itemNodes.indices.contains(pressed.index) {
            itemNodes[pressed.index].setScale(1)
            itemNodes[pressed.index].alpha = 1
        }
        guard !cancelled else { return nil }
        if menu.kind == .gameOver { return Choice(index: 0, step: 1) }
        let p = touch.location(in: self)
        guard itemFrames.indices.contains(pressed.index), itemFrames[pressed.index].contains(p) else { return nil }
        guard menu.items[pressed.index].isAdjustable else { return Choice(index: pressed.index, step: 1) }
        if decrementFrames[pressed.index]?.contains(p) == true { return Choice(index: pressed.index, step: -1) }
        if incrementFrames[pressed.index]?.contains(p) == true { return Choice(index: pressed.index, step: 1) }
        // The label or the value: select the row, never change it.
        return Choice(index: pressed.index, step: 0)
    }

    // MARK: Layout

    private struct Metrics {
        let heading: CGFloat
        let item: CGFloat
        let body: CGFloat
        var itemHeight: CGFloat
        var gap: CGFloat
        var lineHeight: CGFloat
        let margin: CGFloat
    }

    private func rebuild(_ menu: Menu, size: CGSize, safeArea: UIEdgeInsets, keepClear: ClosedRange<CGFloat>?) {
        removeAllChildren()
        itemFrames = []
        itemNodes = []
        decrementFrames = [:]
        incrementFrames = [:]

        let short = min(size.width, size.height)
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
        var m = Metrics(
            heading: clamp(short * 0.085, 26, 52),
            item: clamp(short * 0.045, 16, 22),
            body: clamp(short * 0.04, 14, 19),
            itemHeight: 0, gap: clamp(short * 0.02, 6, 12), lineHeight: 0,
            margin: max(16, short * 0.04)
        )
        m.itemHeight = max(46, m.item * 2.4)
        m.lineHeight = m.body * 1.55

        let content = CGRect(x: safeArea.left + m.margin, y: safeArea.bottom + m.margin,
                             width: size.width - safeArea.left - safeArea.right - 2 * m.margin,
                             height: size.height - safeArea.top - safeArea.bottom - 2 * m.margin)
        guard content.width > 0, content.height > 0 else { return }

        // High scores put their table beside the items; every other menu puts its lines under the heading.
        let tableBesideItems = menu.kind == .highScores
        let headingLines = tableBesideItems ? [] : menu.lines
        let listLines = tableBesideItems ? menu.lines : []
        // Room is kept for the most detail lines any item has, so the heading stays put as the
        // selection moves.
        let reserved = headingLines.count + (menu.items.map(\.details.count).max() ?? 0)
        func clampSide(_ v: CGFloat, _ hi: CGFloat) -> CGFloat { menu.kind == .title ? clamp(v, 56, hi) : 0 }

        if size.width > size.height * 1.1 {
            let middleLow = keepClear?.lowerBound ?? size.width / 2
            let middleHigh = keepClear?.upperBound ?? size.width / 2
            let left = CGRect(x: content.minX, y: content.minY,
                              width: max(middleLow - m.margin - content.minX, 60), height: content.height)
            let right = CGRect(x: middleHigh + m.margin, y: content.minY,
                               width: max(content.maxX - middleHigh - m.margin, 60), height: content.height)
            let emblem = clampSide(min(left.width * 0.5, left.height * 0.34), 200)
            let headingBlock = blockHeight(lines: reserved, m: m, withHeading: true, menu: menu, emblem: emblem)
            placeHeading(menu, lines: headingLines, reserved: reserved, emblem: emblem, centerX: left.midX,
                         top: left.midY + headingBlock / 2, m: m, maxWidth: left.width)
            placeItems(menu, lines: listLines, in: right, m: m)
        } else {
            let emblem = clampSide(min(content.width * 0.42, content.height * 0.2), 180)
            let top = content.maxY - (emblem > 0 ? 0 : m.heading * 0.4)
            let used = placeHeading(menu, lines: headingLines, reserved: reserved, emblem: emblem,
                                    centerX: content.midX, top: top, m: m, maxWidth: content.width)
            let rest = CGRect(x: content.minX, y: content.minY, width: content.width,
                              height: max(top - used - m.gap * 2 - content.minY, 60))
            placeItems(menu, lines: listLines, in: rest, m: m)
        }
    }

    private func blockHeight(lines: Int, m: Metrics, withHeading: Bool, menu: Menu, emblem: CGFloat) -> CGFloat {
        var height = (withHeading ? m.heading * 1.3 : 0) + (lines > 0 ? m.gap + CGFloat(lines) * m.lineHeight : 0)
        if emblem > 0 { height += emblem + m.gap }
        if menu.kind == .title { height += m.heading * 0.35 * 1.3 }
        if menu.subtitle != nil { height += m.lineHeight * 1.1 }
        if menu.kind == .gameOver, lines > 0 { height += m.lineHeight * 0.4 }
        return height
    }

    /// Places the emblem (side `emblem`, none at 0), the heading, the subtitle, `lines` and the
    /// selection's detail lines going down from `top`, keeping room for `reserved` lines. Returns
    /// the height used.
    @discardableResult
    private func placeHeading(_ menu: Menu, lines: [String], reserved: Int, emblem: CGFloat, centerX: CGFloat,
                              top: CGFloat, m: Metrics, maxWidth: CGFloat) -> CGFloat {
        var y = top
        if emblem > 0 {
            let node = EmblemNode()
            node.show(side: emblem)
            node.position = CGPoint(x: centerX, y: y - emblem / 2)
            addChild(node)
            y -= emblem + m.gap
        }
        let lines = lines + menu.detailLines
        let headingText = menu.heading.uppercased()
        var headingSize = menu.kind == .title ? m.heading * 1.35 : m.heading
        // Shrink a heading that would not fit its panel.
        let natural = GlowText.width(of: headingText, style: .heading(headingSize))
        if natural > maxWidth { headingSize = max(headingSize * maxWidth / natural, 16) }
        let heading = GlowText.sprite(headingText, style: .heading(headingSize), color: headingColor)
        heading.position = CGPoint(x: centerX, y: y - headingSize * 0.65)
        addChild(heading)
        y -= headingSize * 1.3

        if let subtitle = menu.subtitle {
            // A quieter line under the heading.
            var subtitleSize = m.body * 0.95
            let text = subtitle.uppercased()
            let style = { (size: CGFloat) in GlowText.Style(size: size, weight: .regular, tracking: 0.22) }
            let natural = GlowText.width(of: text, style: style(subtitleSize))
            if natural > maxWidth { subtitleSize = max(subtitleSize * maxWidth / natural, 10) }
            let line = GlowText.sprite(text, style: style(subtitleSize), color: shellStyle.text.scaled(0.8))
            line.position = CGPoint(x: centerX, y: y - m.lineHeight * 0.4)
            addChild(line)
            y -= m.lineHeight * 1.1
        }

        if !lines.isEmpty { y -= m.gap }
        for (index, line) in lines.enumerated() {
            // A new high score stands out; the final score on game over is larger.
            let isPlacement = line.hasPrefix("New high score")
            let isBest = menu.kind == .title && line.hasPrefix("Best")
            let color = isPlacement || isBest ? shellStyle.highlight : accent.lightened(0.3)
            var style: GlowText.Style = index == 0 ? .item(m.body * 1.1) : .body(m.body)
            var height = m.lineHeight
            if menu.kind == .gameOver, index == 0 {
                style = .item(m.body * 1.55)
                height = m.lineHeight * 1.4
            }
            if isPlacement { style = .item(m.body * 1.15) }
            let natural = GlowText.width(of: line, style: style)
            if natural > maxWidth { style.size = max(style.size * maxWidth / natural, 10) }
            let label = GlowText.sprite(line, style: style, color: color)
            label.position = CGPoint(x: centerX, y: y - height / 2)
            if isPlacement {
                label.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.5),
                                                    .fadeAlpha(to: 1, duration: 0.5)])))
            }
            addChild(label)
            y -= height
        }
        if lines.count < reserved {
            if lines.isEmpty { y -= m.gap }
            y -= CGFloat(reserved - lines.count) * m.lineHeight
        }
        return top - y
    }

    /// How option rows are drawn at the panel's width.
    private struct RowFit {
        /// Font size for every item in this menu.
        var size: CGFloat
        /// Label on one line, "‹ value ›" on a second line below it.
        var reflow: Bool
        /// Width kept for the value between the arrows, so the arrows don't move as it changes.
        var valueWidth: CGFloat
        /// Font size of the label in a two-line row (it can shrink to fit the panel's height).
        var labelSize: CGFloat
        /// Height of a two-line row's label band.
        var labelBand: CGFloat { labelSize * 1.3 }
    }

    /// Spacing in an option row that keeps each arrow's 44 pt touch target clear of the label,
    /// the value and the row's edge.
    private struct ArrowGeometry {
        static let halfTarget: CGFloat = 22
        let leftInset: CGFloat
        /// From the row's right edge to the up arrow's glyph.
        let rightInset: CGFloat
        /// Between each arrow glyph and the value slot.
        let armGap: CGFloat
        /// Between the label and the down arrow glyph.
        let labelGap: CGFloat

        init(size: CGFloat, arrow: CGFloat) {
            let reach = Self.halfTarget - arrow / 2
            leftInset = size * 0.8
            rightInset = max(size * 0.8, reach)
            armGap = max(size * 0.6, reach)
            labelGap = max(size * 0.9, reach + 4)
        }
    }

    /// How far a two-line row's label sits below the row's top, inside the item's outline.
    private static let boxInset: CGFloat = 4

    /// The widest value an option can show. Space is kept for it so the arrows stay put.
    private static let valueReserve = "Standard"

    /// Picks one font size for the items so the widest option row fits `width`: shrink first,
    /// then put the value on a second line if the text would get too small.
    private func fitRows(_ items: [MenuItem], width: CGFloat, size: CGFloat) -> RowFit {
        let options = items.filter { $0.value != nil }
        func widths(_ size: CGFloat) -> (label: CGFloat, cluster: CGFloat, value: CGFloat, arrow: CGFloat) {
            let style = GlowText.Style.item(size)
            let arrow = GlowText.width(of: "‹", style: style)
            let label = options.map { GlowText.width(of: $0.label.uppercased(), style: style) }.max() ?? 0
            let value = (options.map { GlowText.width(of: $0.value ?? "", style: style) }
                + [GlowText.width(of: Self.valueReserve, style: style)]).max() ?? 0
            let geometry = ArrowGeometry(size: size, arrow: arrow)
            return (label, 2 * arrow + value + 2 * geometry.armGap, value, arrow)
        }
        func oneLine(_ size: CGFloat) -> CGFloat {
            let w = widths(size)
            let geometry = ArrowGeometry(size: size, arrow: w.arrow)
            return geometry.leftInset + w.label + geometry.labelGap + w.cluster + geometry.rightInset
        }
        guard !options.isEmpty else { return RowFit(size: size, reflow: false, valueWidth: 0, labelSize: size) }
        let minimum: CGFloat = 12
        var fitted = size
        if oneLine(fitted) > width { fitted = max(size * width / oneLine(size), minimum) }
        if oneLine(fitted) <= width + 0.5 {
            return RowFit(size: fitted, reflow: false, valueWidth: widths(fitted).value, labelSize: fitted)
        }
        // Two lines: each line only has to fit on its own.
        func twoLine(_ size: CGFloat) -> CGFloat {
            let w = widths(size)
            let geometry = ArrowGeometry(size: size, arrow: w.arrow)
            return max(2 * geometry.leftInset + w.label, geometry.leftInset + w.cluster + geometry.rightInset)
        }
        var two = size
        if twoLine(two) > width { two = max(size * width / twoLine(size), 9) }
        return RowFit(size: two, reflow: true, valueWidth: widths(two).value, labelSize: two)
    }

    /// Stacks `lines`, the table (if any), then the items, centred vertically in `rect`, shrinking
    /// spacing if needed.
    private func placeItems(_ menu: Menu, lines: [String], in rect: CGRect, m: Metrics) {
        var m = m
        let count = CGFloat(menu.items.count)
        // Room either side for the selection chevrons.
        let width = min(rect.width - m.item * 3.2, 380)
        var fit = fitRows(menu.items, width: width, size: m.item)
        let optionCount = CGFloat(menu.items.filter { $0.value != nil }.count)
        let plainCount = count - optionCount
        // A two-line option row: the label on a band at the top, then a 44 pt band for the arrows
        // and the value (it may reach into half the gap below the row).
        func optionHeight() -> CGFloat {
            fit.reflow ? 2 * ArrowGeometry.halfTarget - m.gap / 2 + fit.labelBand + Self.boxInset : m.itemHeight
        }

        let table = menu.table.map { prepareTable($0, width: rect.width, body: m.body) }
        var tableLine = table.map { $0.size * 1.55 } ?? 0
        func tableHeight() -> CGFloat {
            guard let table else { return 0 }
            return CGFloat(table.rows.count + 1) * tableLine + m.gap * 1.5
        }
        func needed() -> CGFloat {
            CGFloat(lines.count) * m.lineHeight + (lines.isEmpty ? 0 : m.gap * 1.5) + tableHeight()
                + plainCount * m.itemHeight + optionCount * optionHeight() + max(count - 1, 0) * m.gap
        }
        if needed() > rect.height {
            m.gap = 4
            m.lineHeight = max(m.body * 1.25, 16)
            if let table { tableLine = max(table.size * 1.25, 13) }
            // Plain rows give way first (never below 40 pt, which with the gaps keeps 44 pt targets).
            let shrinking = fit.reflow ? plainCount : count
            var spare = rect.height - needed()
            if spare < 0, shrinking > 0 { m.itemHeight = max(40, m.itemHeight + spare / shrinking) }
            // Then a two-line row's label band gets smaller; the arrow band never does.
            spare = rect.height - needed()
            if spare < 0, fit.reflow, optionCount > 0 {
                fit.labelSize = max(9, fit.labelSize + spare / optionCount / 1.3)
            }
        }
        var y = rect.midY + min(needed(), rect.height) / 2

        for line in lines {
            let label = GlowText.sprite(line, style: .body(m.body), color: accent.lightened(0.3))
            label.position = CGPoint(x: rect.midX, y: y - m.lineHeight / 2)
            addChild(label)
            y -= m.lineHeight
        }
        if !lines.isEmpty { y -= m.gap * 1.5 }
        if let table {
            y -= placeTable(table, centerX: rect.midX, top: y, lineHeight: tableLine)
            y -= m.gap * 1.5
        }

        for (index, item) in menu.items.enumerated() {
            let height = item.value != nil ? optionHeight() : m.itemHeight
            let frame = CGRect(x: rect.midX - width / 2, y: y - height, width: width, height: height)
            let node = makeItem(item, selected: menu.selection == index, frame: frame, m: m, fit: fit, index: index)
            addChild(node)
            itemNodes.append(node)
            // Touch targets reach halfway into the gaps.
            itemFrames.append(frame.insetBy(dx: 0, dy: -m.gap / 2))
            y -= height + m.gap
        }
    }

    // MARK: Table

    private struct PreparedTable {
        var columns: [MenuTable.Column]
        var rows: [[String]]
        var widths: [CGFloat]
        var gap: CGFloat
        var size: CGFloat
        var highlighted: Int?
        var total: CGFloat { widths.reduce(0, +) + gap * CGFloat(max(widths.count - 1, 0)) }
    }

    /// Chooses the columns and font size that fit `width`: lower-priority columns go first, then
    /// the text shrinks.
    private func prepareTable(_ table: MenuTable, width: CGFloat, body: CGFloat) -> PreparedTable {
        var keep = Array(table.columns.indices)
        func build(_ size: CGFloat) -> PreparedTable {
            let style = GlowText.Style.body(size)
            let header = GlowText.Style.body(size * 0.85)
            let widths = keep.map { column in
                let cells = table.rows.map { GlowText.width(of: $0[column], style: style) }
                return max(cells.max() ?? 0, GlowText.width(of: table.columns[column].title.uppercased(), style: header))
            }
            return PreparedTable(columns: keep.map { table.columns[$0] }, rows: table.rows.map { row in keep.map { row[$0] } },
                                 widths: widths, gap: size * 1.3, size: size, highlighted: table.highlightedRow)
        }
        var size = body
        var prepared = build(size)
        while prepared.total > width, keep.count > 2,
              let drop = keep.indices.min(by: { table.columns[keep[$0]].priority < table.columns[keep[$1]].priority }) {
            keep.remove(at: drop)
            prepared = build(size)
        }
        if prepared.total > width {
            size = max(size * width / prepared.total, 9)
            prepared = build(size)
        }
        return prepared
    }

    /// Draws the table from `top` down. Returns the height used.
    private func placeTable(_ table: PreparedTable, centerX: CGFloat, top: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let left = centerX - table.total / 2
        var y = top
        func place(_ cells: [String], style: GlowText.Style, color: RGB) {
            var x = left
            for (index, cell) in cells.enumerated() {
                let sprite = GlowText.sprite(cell, style: style, color: color)
                let w = table.widths[index]
                switch table.columns[index].alignment {
                case .leading:
                    sprite.anchorPoint = CGPoint(x: 0, y: 0.5)
                    sprite.position = CGPoint(x: x - GlowText.padding, y: y - lineHeight / 2)
                case .trailing:
                    sprite.anchorPoint = CGPoint(x: 1, y: 0.5)
                    sprite.position = CGPoint(x: x + w + GlowText.padding, y: y - lineHeight / 2)
                }
                addChild(sprite)
                x += w + table.gap
            }
            y -= lineHeight
        }
        place(table.columns.map { $0.title.uppercased() }, style: .body(table.size * 0.85), color: accent.scaled(0.75))
        for (index, row) in table.rows.enumerated() {
            let isLatest = index == table.highlighted
            if isLatest {
                // The most recent run: a soft bar behind the row and a marker beside it.
                let bar = SKSpriteNode(color: shellStyle.highlight.uiColor(),
                                       size: CGSize(width: table.total + table.gap, height: lineHeight * 0.92))
                bar.alpha = 0.13
                bar.blendMode = .add
                bar.position = CGPoint(x: centerX, y: y - lineHeight / 2)
                addChild(bar)
                let mark = GlowText.sprite("›", style: .item(table.size), color: shellStyle.highlight)
                mark.position = CGPoint(x: left - table.gap * 0.9, y: y - lineHeight / 2)
                addChild(mark)
            }
            place(row, style: isLatest ? .item(table.size) : .body(table.size),
                  color: isLatest ? shellStyle.highlight : accent.lightened(0.3))
        }
        return top - y
    }

    private func makeItem(_ item: MenuItem, selected: Bool, frame: CGRect, m: Metrics, fit: RowFit,
                          index: Int) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: frame.midX, y: frame.midY)
        let enabled = item.isEnabled
        let color = enabled ? accent : accent.scaled(0.55)

        let box = GlowFrame.sprite(size: CGSize(width: frame.width, height: frame.height - 6), color: color,
                                   cut: min(12, frame.height * 0.25))
        box.alpha = !enabled ? 0.35 : (selected ? 1 : 0.5)
        node.addChild(box)

        if selected {
            // Chevrons either side mark the selection (what a gamepad's A would activate).
            for side in [-1.0, 1.0] {
                let mark = GlowText.sprite(side < 0 ? "›" : "‹", style: .item(m.item), color: accent)
                mark.position = CGPoint(x: side * (frame.width / 2 + m.item * 0.9), y: 0)
                node.addChild(mark)
            }
        }

        let style = GlowText.Style.item(fit.size)
        let labelStyle = item.value != nil && fit.reflow ? GlowText.Style.item(fit.labelSize) : style
        let label = GlowText.sprite(item.label.uppercased(), style: labelStyle,
                                    color: enabled ? accent.lightened(0.2) : color)
        label.alpha = enabled ? 1 : 0.6

        guard let value = item.value else {
            // Plain items shrink their label if it would not fit the box.
            let natural = GlowText.width(of: item.label.uppercased(), style: style)
            if natural > frame.width - fit.size * 1.6 { label.setScale((frame.width - fit.size * 1.6) / natural) }
            node.addChild(label)
            return node
        }

        // Option row: name on the left, "‹ value ›" on the right (or on a second line when the
        // panel is narrow). The value sits in a fixed-width slot so the arrows never move. The
        // left arrow steps down; a touch anywhere else on the row steps up.
        let arrowW = GlowText.width(of: "‹", style: style)
        let geometry = ArrowGeometry(size: fit.size, arrow: arrowW)
        // Two lines: the arrow band is the bottom 44 pt (reaching half the gap below the row); the
        // label sits in the band above it.
        let half = ArrowGeometry.halfTarget
        let bandBottom = -frame.height / 2 - m.gap / 2
        let labelY: CGFloat = fit.reflow ? frame.height / 2 - Self.boxInset - fit.labelBand / 2 : 0
        let valueY: CGFloat = fit.reflow ? bandBottom + half : 0
        label.anchorPoint = CGPoint(x: 0, y: 0.5)
        label.position = CGPoint(x: -frame.width / 2 + geometry.leftInset - GlowText.padding, y: labelY)
        node.addChild(label)

        let upX = frame.width / 2 - geometry.rightInset - arrowW / 2
        let valueCenter = upX - arrowW / 2 - geometry.armGap - fit.valueWidth / 2
        let downX = valueCenter - fit.valueWidth / 2 - geometry.armGap - arrowW / 2
        let up = GlowText.sprite("›", style: style, color: accent)
        up.position = CGPoint(x: upX, y: valueY)
        node.addChild(up)
        let valueSprite = GlowText.sprite(value, style: style, color: shellStyle.highlight)
        valueSprite.position = CGPoint(x: valueCenter, y: valueY)
        node.addChild(valueSprite)
        let down = GlowText.sprite("‹", style: style, color: accent)
        down.position = CGPoint(x: downX, y: valueY)
        node.addChild(down)

        // Each arrow's touch target is 44 pt wide, centred on the arrow. The spacing above keeps
        // both clear of the label and the value text, so a touch there only selects the row.
        // On two lines the label is on the top line, so the targets take the bottom half.
        let minY = frame.minY - m.gap / 2
        let height = fit.reflow ? 2 * half : frame.height + m.gap
        decrementFrames[index] = CGRect(x: frame.midX + downX - half, y: minY, width: 2 * half, height: height)
        incrementFrames[index] = CGRect(x: frame.midX + upX - half, y: minY, width: 2 * half, height: height)
        return node
    }
}
