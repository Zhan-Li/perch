import AppKit
import ApplicationServices

/// Watches the global mouse and reports genuine window drags.
///
/// The hard part is not noticing the mouse move — it is telling a *window* drag
/// apart from selecting text, dragging a file, or panning a canvas. We do that
/// by only arming once the window under the initial click has actually changed
/// position. Nothing else moves a window, so there are no false positives, and
/// the cost is a handful of Accessibility reads at the start of each drag.
final class DragMonitor {

    var onBegan: ((CGPoint) -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onEnded: ((AXUIElement, CGPoint) -> Void)?
    var onCancelled: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private var downPoint: CGPoint = .zero
    private var pending = false
    private var armed = false
    private var candidate: AXUIElement?
    private var candidateOrigin: CGPoint?

    /// Past this many points of cursor travel we give up looking for a window
    /// drag — whatever this gesture is, it isn't one.
    private let resolveDistance: CGFloat = 4
    private let movedThreshold: CGFloat = 2

    // MARK: - Tap

    /// Whether the tap is live. This doubles as the app's notion of "are we
    /// working", because a live tap is exactly what Accessibility access buys.
    var isRunning: Bool { tap != nil }

    /// Safe to call repeatedly: returns true immediately if already tapped, and
    /// otherwise attempts to create the tap, which only succeeds once the user
    /// has granted Accessibility access.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<DragMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        reset()
    }

    // MARK: - State machine

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap that takes too long in its callback; the
        // only recovery is to switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let location = event.location

        switch type {
        case .leftMouseDown:
            reset()
            downPoint = location
            pending = true

        case .leftMouseDragged:
            guard pending || armed else { return }
            if armed {
                onMoved?(location)
            } else {
                advanceTowardsArming(cursor: location)
            }

        case .leftMouseUp:
            if armed, let window = candidate {
                onEnded?(window, location)
            } else if armed {
                onCancelled?()
            }
            reset()

        default:
            break
        }
    }

    private func advanceTowardsArming(cursor: CGPoint) {
        if candidate == nil {
            guard hypot(cursor.x - downPoint.x, cursor.y - downPoint.y) >= resolveDistance else { return }
            guard let window = AX.window(at: downPoint),
                  AX.pid(window) != ProcessInfo.processInfo.processIdentifier,
                  AX.isMovable(window),
                  let origin = AX.origin(window) else {
                pending = false
                return
            }
            candidate = window
            candidateOrigin = origin
        }

        guard let window = candidate, let start = candidateOrigin, let now = AX.origin(window) else {
            pending = false
            return
        }

        if hypot(now.x - start.x, now.y - start.y) > movedThreshold {
            armed = true
            onBegan?(cursor)
        }
    }

    private func reset() {
        pending = false
        armed = false
        candidate = nil
        candidateOrigin = nil
    }
}
