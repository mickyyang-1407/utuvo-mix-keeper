import AppKit
import MixKeeperCore

/// 不搶焦點、所有桌面都看得到的透明小視窗。
final class KeeperPanel: NSPanel {
    init(size: NSSize, level: NSWindow.Level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum PetPose: String, CaseIterable {
    case idle, sleep, alert
}

enum PetCharacter: String, CaseIterable {
    case tape, speaker, cat, guitar, trumpet, drum, piano, sax, cello

    var title: String {
        switch self {
        case .tape: return L.t("磁帶小怪", "Tape Imp")
        case .speaker: return L.t("小喇叭精靈", "Speaker Sprite")
        case .cat: return L.t("推桿小貓", "Fader Kitty")
        case .guitar: return L.t("電吉他小子", "Guitar Kid")
        case .trumpet: return L.t("小號大嘴", "Big-Mouth Trumpet")
        case .drum: return L.t("小鼓胖胖", "Chubby Snare")
        case .piano: return L.t("鋼琴牙牙", "Toothy Piano")
        case .sax: return L.t("薩克斯懶懶", "Lazy Sax")
        case .cello: return L.t("大提琴害羞鬼", "Shy Cello")
        }
    }

    static var saved: PetCharacter {
        get { UserDefaults.standard.string(forKey: "character").flatMap(PetCharacter.init) ?? .tape }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "character") }
    }
}

final class PetView: NSView {
    // 翻面放內層、動畫放外層：同一層的鏡像會讓 transform.scale.y 動畫在正負之間擺盪，角色被壓扁、翻出視窗。
    private let motionLayer = CALayer()
    private let imageLayer = CALayer()
    var images: [PetPose: NSImage]
    /// 逐格走路圖（面向右）。沒有就只用搖擺。
    var walkFrames: [NSImage] = []
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var dragged = false
    private var rubMoves = 0

    var onClick: () -> Void = {}
    var onDrag: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onPetted: () -> Void = {}

    var facingLeft = false {
        didSet { imageLayer.setAffineTransform(CGAffineTransform(scaleX: facingLeft ? -1 : 1, y: 1)) }
    }

    init(frame: NSRect, images: [PetPose: NSImage]) {
        self.images = images
        super.init(frame: frame)
        wantsLayer = true
        motionLayer.anchorPoint = CGPoint(x: 0.5, y: 0)  // 從腳底擺動
        motionLayer.bounds = bounds
        motionLayer.position = CGPoint(x: bounds.midX, y: 0)
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resizeAspect
        motionLayer.addSublayer(imageLayer)
        layer?.addSublayer(motionLayer)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ pose: PetPose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = images[pose]
        CATransaction.commit()
        motionLayer.removeAnimation(forKey: "motion")
        let motion = CABasicAnimation(keyPath: pose == .alert ? "position.y" : "transform.scale.y")
        motion.autoreverses = true
        motion.repeatCount = .infinity
        motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        switch pose {
        case .alert:
            motion.byValue = 7
            motion.duration = 0.18
        case .sleep:
            motion.toValue = 0.97
            motion.duration = 1.9
        case .idle:
            motion.toValue = 0.985
            motion.duration = 1.1
        }
        motionLayer.add(motion, forKey: "motion")
    }

    /// 每一步前進的距離（點）。步頻跟著速度走，腳才不會原地亂踩。
    static let stride: CGFloat = 34

    var hasLegs: Bool { !walkFrames.isEmpty }

    func setWalking(_ walking: Bool, speed: CGFloat = 100) {
        motionLayer.removeAnimation(forKey: "waddle")
        motionLayer.removeAnimation(forKey: "step")
        imageLayer.removeAnimation(forKey: "legs")
        guard walking else { return }
        let fast = speed > 300
        if hasLegs {
            let perStep = Double(min(max(Self.stride / speed, 0.06), 0.5))
            let legs = CAKeyframeAnimation(keyPath: "contents")
            legs.values = walkFrames
            legs.calculationMode = .discrete
            // 一輪＝兩步（左、右），不管是兩格還是含併攏的四格。
            legs.duration = perStep * 2
            legs.repeatCount = .infinity
            imageLayer.add(legs, forKey: "legs")
            // 每踏一步身體輕輕上下一次，和腳同拍；不左右晃。
            let bob = CABasicAnimation(keyPath: "position.y")
            bob.byValue = fast ? 4 : 2.5
            bob.duration = perStep / 2
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeOut)
            motionLayer.add(bob, forKey: "step")
            return
        }
        let waddle = CABasicAnimation(keyPath: "transform.rotation.z")
        waddle.fromValue = fast ? -0.14 : -0.07
        waddle.toValue = fast ? 0.14 : 0.07
        waddle.duration = fast ? 0.09 : 0.26
        waddle.autoreverses = true
        waddle.repeatCount = .infinity
        waddle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        motionLayer.add(waddle, forKey: "waddle")
        let step = CABasicAnimation(keyPath: "position.y")
        step.byValue = fast ? 7 : 4
        step.duration = waddle.duration / 2
        step.autoreverses = true
        step.repeatCount = .infinity
        motionLayer.add(step, forKey: "step")
    }

    /// 走進門：縮小淡出。
    func fadeOut(done: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.8
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = 0.35
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        motionLayer.add(group, forKey: "door")
        CATransaction.commit()
    }

    /// 從門裡出來。
    func fadeIn() {
        motionLayer.removeAnimation(forKey: "door")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.8
        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.duration = 0.3
        motionLayer.add(group, forKey: "doorIn")
    }

    func hop() {
        let hop = CABasicAnimation(keyPath: "position.y")
        hop.byValue = 18
        hop.duration = 0.14
        hop.autoreverses = true
        motionLayer.add(hop, forKey: "hop")
    }

    func heart() {
        let label = CATextLayer()
        label.string = "♥"
        label.fontSize = 20
        label.foregroundColor = NSColor.systemPink.cgColor
        label.alignmentMode = .center
        label.contentsScale = 2
        label.frame = CGRect(x: bounds.midX - 12 + .random(in: -18...18), y: bounds.maxY - 34, width: 24, height: 26)
        layer?.addSublayer(label)
        CATransaction.begin()
        CATransaction.setCompletionBlock { label.removeFromSuperlayer() }
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.byValue = 26
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.duration = 0.8
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        label.add(group, forKey: nil)
        CATransaction.commit()
    }

    override func mouseMoved(with event: NSEvent) {
        rubMoves += 1
        if rubMoves >= 14 {
            rubMoves = 0
            onPetted()
        }
    }

    override func mouseExited(with event: NSEvent) { rubMoves = 0 }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart else { return }
        let now = NSEvent.mouseLocation
        let delta = NSPoint(x: now.x - dragStart.x, y: now.y - dragStart.y)
        if hypot(delta.x, delta.y) > 3, !dragged {
            dragged = true
            onDrag()
        }
        if dragged { window?.setFrameOrigin(NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y)) }
    }

    override func mouseUp(with event: NSEvent) {
        dragged ? onDragEnd() : onClick()
    }
}
