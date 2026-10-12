import MellonCore
import SwiftUI
import UIKit

enum TrackpadEvent {
    case move(dx: Double, dy: Double)
    case scroll(dx: Double, dy: Double)
    case click(MouseButton)
    case dragBegan
    case dragEnded
}

/// Multi-touch surface that behaves like a Mac trackpad.
struct TrackpadSurface: UIViewRepresentable {
    let onEvent: (TrackpadEvent) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    @MainActor
    final class Coordinator: NSObject {
        var onEvent: (TrackpadEvent) -> Void
        private var lastDragLocation: CGPoint?
        private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
        private let dragFeedback = UIImpactFeedbackGenerator(style: .medium)

        init(onEvent: @escaping (TrackpadEvent) -> Void) { self.onEvent = onEvent }

        func install(on view: UIView) {
            let drag = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag))
            drag.minimumPressDuration = 0.35
            drag.allowableMovement = 8

            let move = UIPanGestureRecognizer(target: self, action: #selector(handleMove))
            move.maximumNumberOfTouches = 1
            move.require(toFail: drag)

            let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
            scroll.minimumNumberOfTouches = 2
            scroll.maximumNumberOfTouches = 2

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
            twoFingerTap.numberOfTouchesRequired = 2

            [drag, move, scroll, tap, twoFingerTap].forEach(view.addGestureRecognizer)
        }

        /// Pointer acceleration: slow movements stay precise, fast flicks cross the screen.
        private func accelerated(_ translation: CGPoint) -> (Double, Double) {
            let speed = hypot(translation.x, translation.y)
            let gain = 1.4 + min(speed * 0.12, 3.0)
            return (translation.x * gain, translation.y * gain)
        }

        @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let (dx, dy) = accelerated(gesture.translation(in: gesture.view))
            gesture.setTranslation(.zero, in: gesture.view)
            onEvent(.move(dx: dx, dy: dy))
        }

        @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            // Natural scrolling: content follows the fingers.
            onEvent(.scroll(dx: translation.x * 1.6, dy: translation.y * 1.6))
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            tapFeedback.impactOccurred()
            onEvent(.click(.left))
        }

        @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            tapFeedback.impactOccurred(intensity: 0.8)
            onEvent(.click(.right))
        }

        @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                dragFeedback.impactOccurred()
                lastDragLocation = location
                onEvent(.dragBegan)
            case .changed:
                if let last = lastDragLocation {
                    let (dx, dy) = accelerated(CGPoint(x: location.x - last.x, y: location.y - last.y))
                    onEvent(.move(dx: dx, dy: dy))
                }
                lastDragLocation = location
            case .ended, .cancelled, .failed:
                if lastDragLocation != nil { onEvent(.dragEnded) }
                lastDragLocation = nil
            default:
                break
            }
        }
    }
}

/// Invisible view that shows the system keyboard and forwards every keystroke.
struct KeyboardCapture: UIViewRepresentable {
    @Binding var isActive: Bool
    let onText: (String) -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> KeyCaptureView {
        KeyCaptureView()
    }

    func updateUIView(_ view: KeyCaptureView, context: Context) {
        view.onText = onText
        view.onDelete = onDelete
        DispatchQueue.main.async {
            if isActive, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !isActive, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
}

final class KeyCaptureView: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    // Always report text so the delete key keeps working.
    var hasText: Bool { true }
    func insertText(_ text: String) { onText?(text) }
    func deleteBackward() { onDelete?() }

    // Send exactly what was typed: no autocorrect, capitalization or smart punctuation.
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardAppearance: UIKeyboardAppearance = .dark
}
