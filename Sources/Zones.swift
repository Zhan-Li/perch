import AppKit

/// A drop target, expressed as a rectangle of cells on a grid. `Zone(cols: 3,
/// rows: 1, x: 0, y: 0, w: 2, h: 1)` is "the left two thirds".
///
/// Cell coordinates run left-to-right and top-to-bottom, matching the Quartz
/// space we place windows in.
struct Zone: Codable, Equatable {
    var name: String
    var cols: Int
    var rows: Int
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    /// Where a window assigned to this zone should end up inside `area`, which
    /// is a screen's usable region in Quartz coordinates.
    func frame(in area: CGRect) -> CGRect {
        let cellWidth = area.width / CGFloat(cols)
        let cellHeight = area.height / CGFloat(rows)
        return CGRect(
            x: (area.minX + CGFloat(x) * cellWidth).rounded(),
            y: (area.minY + CGFloat(y) * cellHeight).rounded(),
            width: (CGFloat(w) * cellWidth).rounded(),
            height: (CGFloat(h) * cellHeight).rounded()
        )
    }

    /// The same rectangle in 0...1 units, for drawing the icon preview.
    /// y is measured from the top, as above.
    var unitRect: CGRect {
        CGRect(
            x: CGFloat(x) / CGFloat(cols),
            y: CGFloat(y) / CGFloat(rows),
            width: CGFloat(w) / CGFloat(cols),
            height: CGFloat(h) / CGFloat(rows)
        )
    }

    var isValid: Bool {
        cols > 0 && rows > 0 && w > 0 && h > 0
            && x >= 0 && y >= 0
            && x + w <= cols && y + h <= rows
    }
}

/// Where the icon strip sits on the display. Centre is the default: it is the
/// shortest trip from wherever the cursor already is when a drag starts.
enum Placement: String, Codable {
    case top
    case center
    case bottom
}

struct Config: Codable {
    var zones: [Zone]
    var iconWidth: Double
    var iconHeight: Double
    var iconGap: Double
    /// Distance from the anchored edge to the icon strip. Ignored when centred.
    var topMargin: Double
    /// Optional so configs written before this setting existed still decode.
    var placement: Placement?
    /// Extra slack around each icon when deciding whether the cursor is over it.
    /// Aiming at a 76pt target mid-drag wants a little forgiveness.
    var hitPadding: Double

    static let fallback = Config(
        zones: [
            Zone(name: "Left Half",       cols: 2, rows: 1, x: 0, y: 0, w: 1, h: 1),
            Zone(name: "Right Half",      cols: 2, rows: 1, x: 1, y: 0, w: 1, h: 1),
            // Sixths, because two thirds centred leaves a third to split evenly
            // either side — it cannot be expressed on a three-column grid.
            Zone(name: "Centred Two Thirds", cols: 6, rows: 1, x: 1, y: 0, w: 4, h: 1),
            Zone(name: "Top Half",        cols: 1, rows: 2, x: 0, y: 0, w: 1, h: 1),
            Zone(name: "Bottom Half",     cols: 1, rows: 2, x: 0, y: 1, w: 1, h: 1),
            Zone(name: "Top Left",        cols: 2, rows: 2, x: 0, y: 0, w: 1, h: 1),
            Zone(name: "Top Right",       cols: 2, rows: 2, x: 1, y: 0, w: 1, h: 1),
            Zone(name: "Bottom Left",     cols: 2, rows: 2, x: 0, y: 1, w: 1, h: 1),
            Zone(name: "Bottom Right",    cols: 2, rows: 2, x: 1, y: 1, w: 1, h: 1),
            Zone(name: "Full Screen",     cols: 1, rows: 1, x: 0, y: 0, w: 1, h: 1),
        ],
        iconWidth: 76,
        iconHeight: 52,
        iconGap: 10,
        topMargin: 60,
        placement: .center,
        hitPadding: 8
    )

    var resolvedPlacement: Placement {
        placement ?? .center
    }

    /// Drops anything malformed rather than refusing to start. A typo in one
    /// zone shouldn't cost you the whole app.
    var sanitized: Config {
        var copy = self
        copy.zones = zones.filter(\.isValid)
        if copy.zones.isEmpty { copy.zones = Config.fallback.zones }
        copy.iconWidth = max(40, iconWidth)
        copy.iconHeight = max(28, iconHeight)
        copy.iconGap = max(0, iconGap)
        copy.topMargin = max(0, topMargin)
        copy.placement = resolvedPlacement
        copy.hitPadding = max(0, hitPadding)
        return copy
    }
}

enum ConfigStore {

    static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
    }

    static var url: URL {
        directory.appendingPathComponent("zones.json")
    }

    /// Reads the config, writing out the defaults the first time so there is
    /// always a file on disk for the user to edit.
    static func load() -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            save(.fallback)
            return .fallback
        }
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .fallback
        }
        return config.sanitized
    }

    static func save(_ config: Config) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}
