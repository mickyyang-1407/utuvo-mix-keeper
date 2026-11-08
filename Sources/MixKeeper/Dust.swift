import AppKit

/// 腳邊揚起的塵土。每團是一個留在原地的小視窗，所以塵土會落在後面，不會黏著角色跑。
final class Dust {
    private static let size = NSSize(width: 72, height: 48)
    private static let color = NSColor(calibratedRed: 0.80, green: 0.70, blue: 0.56, alpha: 1)

    private var pool: [KeeperPanel] = []
    private var next = 0

    init(count: Int = 32) {
        for _ in 0..<count {
            let panel = KeeperPanel(size: Self.size, level: .statusBar)
            panel.ignoresMouseEvents = true
            let view = NSView(frame: NSRect(origin: .zero, size: Self.size))
            view.wantsLayer = true
            panel.contentView = view
            pool.append(panel)
        }
    }

    /// `feet`：腳底中心（螢幕座標）。`back`：往後飄的方向，-1 往左、1 往右。`scale`：大小。
    func puff(at feet: NSPoint, back: CGFloat, scale: CGFloat = 1) {
        let panel = pool[next]
        next = (next + 1) % pool.count
        guard let host = panel.contentView?.layer else { return }
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        panel.setFrameOrigin(NSPoint(x: feet.x - Self.size.width / 2, y: feet.y - 6))
        panel.orderFrontRegardless()

        let cloud = CALayer()
        cloud.frame = host.bounds
        host.addSublayer(cloud)
        for _ in 0..<Int.random(in: 3...4) {
            let radius = CGFloat.random(in: 6...11) * scale
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.cornerRadius = radius
            dot.backgroundColor = Self.color.withAlphaComponent(.random(in: 0.45...0.7)).cgColor
            dot.position = CGPoint(x: host.bounds.midX + .random(in: -10...10) * scale, y: 10 + .random(in: 0...6))
            cloud.addSublayer(dot)
        }

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.35
        grow.toValue = 1.35
        let rise = CABasicAnimation(keyPath: "position")
        rise.byValue = NSValue(point: NSPoint(x: back * .random(in: 6...14) * scale, y: .random(in: 6...12)))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, rise, fade]
        group.duration = .random(in: 0.55...0.8)
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak cloud] in
            // 這個視窗可能已被下一團借走；只收自己的。
            guard let cloud, cloud.superlayer === host else { return }
            cloud.removeFromSuperlayer()
            panel.orderOut(nil)
        }
        cloud.add(group, forKey: "puff")
        CATransaction.commit()
    }
}
