import SwiftUI
import UIKit

struct HoldUndoButton: UIViewRepresentable {
    @EnvironmentObject private var appearance: AppearanceStore
    var undo: () -> Void
    var reset: () -> Void
    @Binding var hint: String

    func makeUIView(context: Context) -> UndoControl { UndoControl() }
    func updateUIView(_ control: UndoControl, context: Context) {
        control.onUndo = undo; control.onReset = reset
        control.onHint = { hint = $0 }
        control.tintColor = appearance.theme.ink
    }
}

final class UndoControl: UIControl {
    var onUndo: (() -> Void)?
    var onReset: (() -> Void)?
    var onHint: ((String) -> Void)?
    private let icon = UIImageView()
    private let ring = CAShapeLayer()
    private var start: TimeInterval?
    private var timer: Timer?
    private var fraction: CGFloat = 0
    private let resetHoldDuration: TimeInterval = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.image = UIImage(systemName: "arrow.uturn.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = 2
        ring.lineCap = .round
        layer.addSublayer(ring)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Undo"
        accessibilityIdentifier = "progress.undo"
        accessibilityHint = "Tap to undo the last progress action. Hold for two seconds and release to reset."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: CGSize { CGSize(width: 48, height: 48) }
    override func tintColorDidChange() { super.tintColorDidChange(); icon.tintColor = tintColor; ring.strokeColor = tintColor.cgColor }
    override func layoutSubviews() {
        super.layoutSubviews(); icon.frame = bounds
        ring.frame = bounds
        ring.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: min(bounds.width, bounds.height) / 2 - 3, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = fraction
        CATransaction.commit()
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        start = CACurrentMediaTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        return true
    }
    private func tick() {
        guard let start else { return }
        let elapsed = CACurrentMediaTime() - start
        fraction = min(1, elapsed / resetHoldDuration); setNeedsLayout()
        if elapsed >= 0.25 {
            let text = elapsed >= resetHoldDuration ? "Release to reset" : "Hold to reset · \(Int(ceil(resetHoldDuration - elapsed)))s"
            onHint?(text)
            if elapsed >= resetHoldDuration && accessibilityValue != text {
                accessibilityValue = text
                UIAccessibility.post(notification: .announcement, argument: text)
            }
        }
    }
    private func cancelHold() {
        timer?.invalidate(); timer = nil; start = nil; fraction = 0
        onHint?(""); accessibilityValue = nil; setNeedsLayout()
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !bounds.contains(touch.location(in: self)) { cancelHold(); return false }
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard let start else { return }
        let elapsed = CACurrentMediaTime() - start
        cancelHold()
        if elapsed < 0.25 { onUndo?() }
        else if elapsed >= resetHoldDuration { onReset?() }
    }
    override func cancelTracking(with event: UIEvent?) { cancelHold() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelHold() } }
    override func accessibilityActivate() -> Bool { onUndo?(); return true }
}
