import Cocoa
import QuartzCore

/// Floating pixel-art tennis ball with bounce physics for Gabi to chase and catch.
final class BallWindowController {
    private let panel: GabiPanel
    private let ballLayer = CALayer()
    private let ballSize: CGFloat = 34

    private(set) var isActive: Bool = false
    private(set) var position: NSPoint = .zero
    private var velocity: NSPoint = .zero
    private var rotation: CGFloat = 0
    private var screenFrame: NSRect = .zero

    init() {
        let p = GabiPanel(
            contentRect: NSRect(x: 0, y: 0, width: ballSize + 8, height: ballSize + 8),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.ignoresMouseEvents = true

        let view = NSView(frame: NSRect(x: 0, y: 0, width: ballSize + 8, height: ballSize + 8))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        ballLayer.bounds = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
        ballLayer.position = CGPoint(x: (ballSize + 8) / 2, y: (ballSize + 8) / 2)
        ballLayer.magnificationFilter = .nearest
        ballLayer.minificationFilter = .nearest
        ballLayer.contents = BallWindowController.makePixelTennisBallImage()
        view.layer?.addSublayer(ballLayer)

        p.contentView = view
        self.panel = p
    }

    func throwBall(from gabiCenter: NSPoint, in screen: NSRect) {
        self.screenFrame = screen
        // Throw away from Gabi toward the roomier side of the screen
        let throwRight = gabiCenter.x < screen.midX
        let dir: CGFloat = throwRight ? 1.0 : -1.0

        position = NSPoint(
            x: gabiCenter.x + dir * 28,
            y: gabiCenter.y + 55
        )
        velocity = NSPoint(
            x: dir * CGFloat.random(in: 380...540),
            y: CGFloat.random(in: 280...420)
        )
        rotation = 0
        isActive = true

        panel.setFrameOrigin(NSPoint(x: position.x - (ballSize + 8) / 2, y: position.y - (ballSize + 8) / 2))
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
    }

    func step(dt: TimeInterval) {
        guard isActive else { return }
        let d = CGFloat(dt)
        let gravity: CGFloat = -1150.0
        let floorY = screenFrame.minY + 18 + ballSize / 2
        let minX = screenFrame.minX + 20
        let maxX = screenFrame.maxX - 20

        velocity.y += gravity * d
        position.x += velocity.x * d
        position.y += velocity.y * d

        // Floor bounce
        if position.y <= floorY {
            position.y = floorY
            if abs(velocity.y) > 90 {
                velocity.y = -velocity.y * 0.62
            } else {
                velocity.y = 0
            }
            // Ground friction
            velocity.x *= pow(0.32, d)
            if abs(velocity.x) < 8 { velocity.x = 0 }
        }

        // Left/right wall bounce
        if position.x < minX {
            position.x = minX
            velocity.x = abs(velocity.x) * 0.72
        } else if position.x > maxX {
            position.x = maxX
            velocity.x = -abs(velocity.x) * 0.72
        }

        // Spin proportionally to horizontal speed
        rotation -= (velocity.x * d) / (ballSize * 0.5)

        panel.setFrameOrigin(NSPoint(
            x: position.x - (ballSize + 8) / 2,
            y: position.y - (ballSize + 8) / 2
        ))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ballLayer.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
        CATransaction.commit()
    }

    func hide() {
        isActive = false
        panel.orderOut(nil)
    }

    /// Generates a crisp 16x16 pixel-art tennis ball CGImage with dark outline & white seams.
    private static func makePixelTennisBallImage() -> CGImage? {
        let size = 16
        // Legend: '.' transparent, 'K' dark outline, 'Y' bright tennis yellow-green,
        // 'L' highlight, 'S' shadow green, 'W' white seam
        let pattern: [String] = [
            ".....KKKKKK.....",
            "...KKLLLLYYKK...",
            "..KLLYYYYYYWWK..",
            ".KLYYYYYYYWYYYK.",
            ".KLYYYYYYWYYYYK.",
            "KLYYYYYYYWYYYYYK",
            "KYYYYYYYYWYYYYYK",
            "KYYWWYYYYWYYYYYK",
            "KYYYYWWYYWYYYYYK",
            "KYYYYYYWWYYYYYSK",
            "KYYYYYYYYYYYYSSK",
            ".KYYYYYYYYYYSSK.",
            ".KYYYYYYYYYSSSK.",
            "..KYYYYYYYSSSK..",
            "...KKSSSSSSKK...",
            ".....KKKKKK....."
        ]

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for (y, row) in pattern.enumerated() {
            for (x, ch) in row.enumerated() {
                let idx = (y * size + x) * 4
                switch ch {
                case "K": pixels[idx] = 24;  pixels[idx+1] = 28;  pixels[idx+2] = 20;  pixels[idx+3] = 255
                case "Y": pixels[idx] = 198; pixels[idx+1] = 232; pixels[idx+2] = 48;  pixels[idx+3] = 255
                case "L": pixels[idx] = 232; pixels[idx+1] = 250; pixels[idx+2] = 120; pixels[idx+3] = 255
                case "S": pixels[idx] = 135; pixels[idx+1] = 178; pixels[idx+2] = 32;  pixels[idx+3] = 255
                case "W": pixels[idx] = 248; pixels[idx+1] = 252; pixels[idx+2] = 244; pixels[idx+3] = 255
                default: break
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
