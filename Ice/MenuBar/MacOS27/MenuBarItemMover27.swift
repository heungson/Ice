// Adapted from fif7y/dimble, ItemMover.swift, revision 57d6ac1 (GPL-3.0).
// https://github.com/fif7y/dimble


import AppKit
import CoreGraphics
import Foundation
import OSLog

@available(macOS 27.0, *)
enum MenuBarItemMover27 {
    static func cmdDrag(from: CGPoint, to: CGPoint, ownItem: Bool = false, jump: Bool = false) async {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.userData = SectionMoveInput27.tag
        let originalPosition = CGEvent(source: nil)?.location

        await waitForPointerQuiet(
            maxWait: ownItem ? 1.5 : 1.5
        )

        let shield = SectionDragShield27()
        shield.activate()
        defer { shield.deactivate() }

        func post(_ type: CGEventType, at point: CGPoint) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { return }
            event.flags = type == .leftMouseUp ? [] : .maskCommand
            event.post(tap: .cghidEventTap)
        }
        func releaseCommand() {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else { return }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }

        post(.leftMouseDown, at: from)
        for _ in 0..<3 {
            shield.reassert()
            try? await Task.sleep(for: .milliseconds(60))
        }
        logSectionMove27("mover: mid-drag cursor \(SectionDragShield27.cursorVisible ? "VISIBLE" : "hidden")")
        let path: [CGPoint]
        if jump {
            path = [to] + (1...5).map { CGPoint(x: to.x + ($0.isMultiple(of: 2) ? 1 : -1), y: to.y) } + [to]
        } else {
            let distance = abs(to.x - from.x) + abs(to.y - from.y)
            let steps = min(24, max(6, Int(distance / 40)))
            path = (1...steps).map { step in
                let t = CGFloat(step) / CGFloat(steps)
                return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            }
        }
        for point in path {
            post(.leftMouseDragged, at: point)
            shield.reassert()
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(120))
        post(.leftMouseUp, at: to)
        releaseCommand()

        try? await Task.sleep(for: .milliseconds(60))
        if let originalPosition {
            CGWarpMouseCursorPosition(originalPosition)
        }
        let flags = CGEventSource.flagsState(.hidSystemState)
        if flags.contains(.maskCommand) {
            logSectionMove27("mover: ⌘ still down after the drag (flags 0x\(String(flags.rawValue, radix: 16)))")
        }
    }

    static func shieldedClick(at point: CGPoint, button: CGMouseButton = .left) async {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.userData = SectionMoveInput27.tag
        let originalPosition = CGEvent(source: nil)?.location
        let shield = SectionDragShield27()
        shield.activate()
        defer { shield.deactivate() }
        let (downType, upType): (CGEventType, CGEventType) =
            button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        func post(_ type: CGEventType) {
            guard let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button
            ) else { return }
            event.post(tap: .cghidEventTap)
        }
        SectionMoveInput27.noteClickPosted()
        post(downType)
        for _ in 0..<2 {
            shield.reassert()
            try? await Task.sleep(for: .milliseconds(30))
        }
        post(upType)
        if let originalPosition {
            try? await Task.sleep(for: .milliseconds(60))
            CGWarpMouseCursorPosition(originalPosition)
        }
    }

    private static func secondsSincePointerActivity() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .scrollWheel,
        ]
        return types.map {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0)
        }.min() ?? .infinity
    }

    private static func waitForPointerQuiet(maxWait: TimeInterval) async {
        let deadline = Date.now.addingTimeInterval(maxWait)
        while Date.now < deadline {
            if secondsSincePointerActivity() >= 0.25 { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        logSectionMove27("mover: pointer never went quiet — dragging shielded anyway")
    }
}


@available(macOS 27.0, *)
enum SectionMoveInput27 {
    static let tag: Int64 = 0x4943_4537 // "ICE7"

    static var clickPostedAt: TimeInterval? { posted.withLock { $0 } }
    private static let posted = OSAllocatedUnfairLock<TimeInterval?>(initialState: nil)

    static func noteClickPosted() {
        posted.withLock { $0 = ProcessInfo.processInfo.systemUptime }
    }
}

@available(macOS 27.0, *)
private final class SectionDragShield27 {

    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapSource: CFRunLoopSource?
    private var active = false
    private let armed = DispatchSemaphore(value: 0)

    private static let backgroundCursorOptIn: Bool = {
        typealias MainCID = @convention(c) () -> UInt32
        typealias SetProp = @convention(c) (UInt32, UInt32, CFString, CFTypeRef) -> Int32
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard
            let cidSym = dlsym(rtldDefault, "CGSMainConnectionID"),
            let setSym = dlsym(rtldDefault, "CGSSetConnectionProperty")
        else {
            logSectionMove27("mover: CGS cursor SPI unresolved — cursor stays visible in background")
            return false
        }
        let cid = unsafeBitCast(cidSym, to: MainCID.self)()
        let err = unsafeBitCast(setSym, to: SetProp.self)(
            cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue
        )
        if err != 0 {
            logSectionMove27("mover: SetsCursorInBackground refused (\(err)) — cursor stays visible in background")
        }
        return err == 0
    }()

    private var hideCount = 0

    static var cursorVisible: Bool {
        typealias IsVisible = @convention(c) () -> UInt32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else {
            return true
        }
        return unsafeBitCast(sym, to: IsVisible.self)() != 0
    }

    func activate() {
        guard !active else { return }
        active = true
        _ = Self.backgroundCursorOptIn
        reassert()
        startTap()
    }

    func reassert() {
        guard active else { return }
        CGAssociateMouseAndMouseCursorPosition(0)
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
    }

    func deactivate() {
        guard active else { return }
        active = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapRunLoop, let tapSource {
            CFRunLoopRemoveSource(tapRunLoop, tapSource, .commonModes)
            CFRunLoopStop(tapRunLoop)
        }
        tap = nil
        tapSource = nil
        tapRunLoop = nil
        while hideCount > 0 {
            CGDisplayShowCursor(CGMainDisplayID())
            hideCount -= 1
        }
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func startTap() {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    return Unmanaged.passUnretained(event)
                }
                if event.getIntegerValueField(.eventSourceUserData) == SectionMoveInput27.tag {
                    return Unmanaged.passUnretained(event)
                }
                return nil // physical mouse input — swallowed for the window
            },
            userInfo: nil
        ) else {
            logSectionMove27("mover: shield tap unavailable — degraded shield")
            return
        }
        self.tap = tap
        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.tapSource = source
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.armed.signal()
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "pelmet.drag-shield"
        thread.start()
        if armed.wait(timeout: .now() + .seconds(1)) == .timedOut {
            logSectionMove27("mover: shield tap never armed — degraded shield")
        }
    }
}

private func logSectionMove27(_ message: String) {
    Logger(subsystem: "com.jordanbaird.Ice", category: "SectionMovement27").debug("\(message, privacy: .public)")
}
