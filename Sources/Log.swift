import Foundation

/// Development logging, off unless explicitly switched on with:
///
///     defaults write com.zhanli.perch debug -bool true
///
/// Writes to /tmp/perch-debug.log so a failing drop can be inspected after the
/// fact — the interesting moment is mid-drag, when a debugger is useless.
enum Log {

    static let isEnabled = UserDefaults.standard.bool(forKey: "debug")

    private static let handle: FileHandle? = {
        guard isEnabled else { return nil }
        let path = "/tmp/perch-debug.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = FileHandle(forWritingAtPath: path)
        handle?.seekToEndOfFile()
        return handle
    }()

    static func write(_ message: String) {
        guard isEnabled, let handle else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        handle.write(Data("\(stamp)  \(message)\n".utf8))
    }
}
