import Cocoa
import QuartzCore

protocol GabiViewDelegate: AnyObject {
    func gabiViewDidClick(_ view: GabiView)
    func gabiViewDidDoubleClick(_ view: GabiView)
    func gabiViewDidStartDrag(_ view: GabiView)
    func gabiViewDidDrag(_ view: GabiView, delta: NSPoint)
    func gabiViewDidEndDrag(_ view: GabiView)
    func gabiViewContextMenu(_ view: GabiView) -> NSMenu?
}

/// Lightweight GPU-backed view: Gabi's sprite and shadow live in CALayers
/// (nearest-neighbor crisp pixel art, zero CPU redraws when still).
/// Only floating particles use a small overlay layer when active.
final class GabiView: NSView {
    weak var delegate: GabiViewDelegate?

    var spriteDrawSize: CGFloat = 148 {
        didSet { layoutLayers() }
    }
    var facingRight: Bool = true {
        didSet {
            if oldValue != facingRight { updateSpriteTransform() }
        }
    }
    var jumpOffsetY: CGFloat = 0 {
        didSet {
            if abs(oldValue - jumpOffsetY) > 0.25 { layoutLayers() }
        }
    }
    var isDragging: Bool = false {
        didSet {
            if oldValue != isDragging {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                shadowLayer.isHidden = isDragging
                CATransaction.commit()
            }
        }
    }
    var currentSprite: CGImage? {
        didSet {
            if oldValue !== currentSprite {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                spriteLayer.contents = currentSprite
                CATransaction.commit()
                layoutLayers()
            }
        }
    }

    var particles: [FloatingParticle] = [] {
        didSet {
            if !particles.isEmpty || !oldValue.isEmpty {
                particleView.particles = particles
                particleView.needsDisplay = true
            }
        }
    }

    var statusBubbleText: String? {
        didSet {
            if oldValue != statusBubbleText {
                particleView.statusBubbleText = statusBubbleText
                particleView.needsDisplay = true
            }
        }
    }

    private let shadowLayer = CAShapeLayer()
    private let spriteLayer = CALayer()
    private let particleView = ParticleOverlayView(frame: .zero)

    private var mouseDownScreenPoint: NSPoint = .zero
    private var lastDragScreenPoint: NSPoint = .zero
    private var didMoveDuringDrag: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        shadowLayer.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(shadowLayer)

        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(spriteLayer)

        particleView.frame = bounds
        particleView.autoresizingMask = [.width, .height]
        addSubview(particleView)

        layoutLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        particleView.frame = bounds
        layoutLayers()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let centerX = bounds.midX
        let baseY: CGFloat = 10

        // Preserve exact pixel-art scale for wider sprites (e.g. 360x256 lying down!)
        let aspect: CGFloat = {
            guard let img = currentSprite, img.height > 0 else { return 1.0 }
            return CGFloat(img.width) / CGFloat(img.height)
        }()
        let drawW = spriteDrawSize * aspect
        let drawH = spriteDrawSize

        let shadowFactor = max(0.45, 1.0 - (jumpOffsetY / 70.0))
        let shadowW = drawW * (aspect > 1.15 ? 0.72 : 0.56) * shadowFactor
        let shadowH = max(8, spriteDrawSize * 0.11 * shadowFactor)
        let shadowRect = CGRect(
            x: centerX - shadowW / 2,
            y: baseY - 2,
            width: shadowW,
            height: shadowH
        )
        shadowLayer.path = CGPath(ellipseIn: shadowRect, transform: nil)
        shadowLayer.opacity = Float(shadowFactor)

        spriteLayer.bounds = CGRect(x: 0, y: 0, width: drawW, height: drawH)
        spriteLayer.position = CGPoint(x: centerX, y: baseY + jumpOffsetY + drawH / 2)
        updateSpriteTransform()

        CATransaction.commit()
    }

    private func updateSpriteTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.transform = facingRight
            ? CATransform3DIdentity
            : CATransform3DMakeScale(-1, 1, 1)
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        mouseDownScreenPoint = screenPoint
        lastDragScreenPoint = screenPoint
        didMoveDuringDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let totalDist = hypot(screenPoint.x - mouseDownScreenPoint.x, screenPoint.y - mouseDownScreenPoint.y)

        if !didMoveDuringDrag && totalDist > 5 {
            didMoveDuringDrag = true
            delegate?.gabiViewDidStartDrag(self)
        }

        if didMoveDuringDrag {
            let delta = NSPoint(
                x: screenPoint.x - lastDragScreenPoint.x,
                y: screenPoint.y - lastDragScreenPoint.y
            )
            lastDragScreenPoint = screenPoint
            delegate?.gabiViewDidDrag(self, delta: delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didMoveDuringDrag {
            didMoveDuringDrag = false
            delegate?.gabiViewDidEndDrag(self)
            return
        }

        if event.clickCount >= 2 {
            delegate?.gabiViewDidDoubleClick(self)
        } else {
            delegate?.gabiViewDidClick(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = delegate?.gabiViewContextMenu(self) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

private final class ParticleOverlayView: NSView {
    var particles: [FloatingParticle] = []
    var statusBubbleText: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        if let text = statusBubbleText, !text.isEmpty {
            let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byWordWrapping

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: para
            ]
            let display = text.count > 130 ? String(text.prefix(129)) + "…" : text
            let attrStr = NSAttributedString(string: display, attributes: attrs)
            let maxTextW = max(120, bounds.width - 24)
            let bounding = attrStr.boundingRect(
                with: NSSize(width: maxTextW, height: 64),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let padX: CGFloat = 10
            let padY: CGFloat = 5
            let pillW = min(bounds.width - 6, ceil(bounding.width) + padX * 2)
            let pillH = min(68, ceil(bounding.height) + padY * 2)
            let pillRect = NSRect(
                x: bounds.midX - pillW / 2,
                y: bounds.height - pillH - 4,
                width: pillW,
                height: pillH
            )
            let radius = min(14, pillH / 2)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)
            NSColor.black.withAlphaComponent(0.80).setFill()
            path.fill()

            let textRect = NSRect(
                x: pillRect.minX + padX,
                y: pillRect.minY + padY,
                width: pillRect.width - padX * 2,
                height: pillRect.height - padY * 2
            )
            attrStr.draw(in: textRect)
        }

        guard !particles.isEmpty else { return }
        for p in particles {
            let font = NSFont.systemFont(ofSize: p.fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: p.color.withAlphaComponent(p.alpha)
            ]
            let str = NSAttributedString(string: p.text, attributes: attrs)
            let size = str.size()
            str.draw(at: NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2))
        }
    }
}
