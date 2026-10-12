import AppKit
import Carbon.HIToolbox
import CoreGraphics
import MellonCore

/// Turns control messages into system input events. Requires the Accessibility permission.
@MainActor
final class InputController {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var pressedButton: MouseButton?
    private var lastClick: (time: TimeInterval, button: MouseButton, count: Int)?

    /// Largest pointer or scroll step accepted from a single message.
    private let maxDelta = 400.0

    func handle(_ message: ControlMessage) {
        switch message {
        case .hello:
            break
        case let .pointerMove(dx, dy):
            movePointer(dx: clamp(dx), dy: clamp(dy))
        case let .click(button):
            click(button)
        case let .buttonDown(button):
            post(button, down: true, clickCount: 1)
            pressedButton = button
        case let .buttonUp(button):
            post(button, down: false, clickCount: 1)
            pressedButton = nil
        case let .scroll(dx, dy):
            scroll(dx: clamp(dx), dy: clamp(dy))
        case let .key(key, modifiers):
            press(keyCode(for: key), flags: flags(for: modifiers))
        case let .text(text):
            type(text)
        case let .media(key):
            postMediaKey(key)
        }
    }

    /// Releases any held button, e.g. when the phone disconnects mid-drag.
    func reset() {
        if let pressedButton { post(pressedButton, down: false, clickCount: 1) }
        pressedButton = nil
    }

    // MARK: Pointer

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -maxDelta), maxDelta)
    }

    private func movePointer(dx: Double, dy: Double) {
        let target = clampToDisplays(CGPoint(x: cursor.x + dx, y: cursor.y + dy))
        let type: CGEventType = switch pressedButton {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        case nil: .mouseMoved
        }
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target,
                            mouseButton: pressedButton == .right ? .right : .left)
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event?.post(tap: .cghidEventTap)
    }

    private func clampToDisplays(_ point: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let bounds = displays.map(CGDisplayBounds)
        if bounds.contains(where: { $0.contains(point) }) || bounds.isEmpty { return point }
        return bounds
            .map { CGPoint(x: min(max(point.x, $0.minX), $0.maxX - 1), y: min(max(point.y, $0.minY), $0.maxY - 1)) }
            .min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }!
    }

    private func click(_ button: MouseButton) {
        let now = ProcessInfo.processInfo.systemUptime
        var count = 1
        if let last = lastClick, last.button == button, now - last.time < NSEvent.doubleClickInterval {
            count = min(last.count + 1, 3)
        }
        lastClick = (now, button, count)
        post(button, down: true, clickCount: count)
        post(button, down: false, clickCount: count)
    }

    private func post(_ button: MouseButton, down: Bool, clickCount: Int) {
        let type: CGEventType = switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        }
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cursor,
                            mouseButton: button == .left ? .left : .right)
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event?.post(tap: .cghidEventTap)
    }

    private func scroll(dx: Double, dy: Double) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    // MARK: Keyboard

    private func keyCode(for key: Key) -> CGKeyCode {
        let code = switch key {
        case .returnKey: kVK_Return
        case .delete: kVK_Delete
        case .forwardDelete: kVK_ForwardDelete
        case .escape: kVK_Escape
        case .tab: kVK_Tab
        case .space: kVK_Space
        case .left: kVK_LeftArrow
        case .right: kVK_RightArrow
        case .up: kVK_UpArrow
        case .down: kVK_DownArrow
        case .home: kVK_Home
        case .end: kVK_End
        case .pageUp: kVK_PageUp
        case .pageDown: kVK_PageDown
        }
        return CGKeyCode(code)
    }

    private func flags(for modifiers: [Modifier]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
    }

    private func press(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Types arbitrary Unicode text, independent of the Mac's keyboard layout.
    private func type(_ text: String) {
        let units = Array(text.utf16)
        // Key events carry at most 20 UTF-16 units each.
        for start in stride(from: 0, to: units.count, by: 20) {
            var chunk = Array(units[start..<min(start + 20, units.count)])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: Media keys

    private func postMediaKey(_ key: MediaKey) {
        // NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h.
        let code: Int = switch key {
        case .volumeUp: 0
        case .volumeDown: 1
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (code << 16) | (state << 8), data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
