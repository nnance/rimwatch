import GameCore
import SpriteKit
import UIKit

/// The one SpriteKit scene. It hands the frame, the touches, the fold pose and its geometry to
/// the mode's driver, which runs the screen flow and the mode.
@MainActor
final class ShellScene: SKScene {
    var safeAreaInsets: UIEdgeInsets = .zero {
        didSet { if safeAreaInsets != oldValue { driver.layout() } }
    }

    /// Scene x range of the crease on an open Duo, kept clear of controls and menu items.
    var keepClear: ClosedRange<CGFloat>? {
        didSet { if keepClear != oldValue { driver.layout() } }
    }

    let services: ShellServices
    private let driver: any ModeDriver

    init(size: CGSize, entry: ModeRegistry.Entry) {
        services = ShellServices(factory: GlowShapeFactory(screenScale: 2), style: entry.style)
        driver = entry.make(services)
        super.init(size: size)
        services.scene = self
        backgroundColor = entry.style.background.uiColor()
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        driver.attach()
    }

    /// The fold gate's verdict. The first call reveals the game.
    func setPose(_ pose: FoldPose) {
        driver.setPose(pose)
    }

    /// The app is losing focus or going to the background.
    func appWillResignActive() {
        driver.appWillResignActive()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        driver.layout()
    }

    override func update(_ currentTime: TimeInterval) {
        driver.frame(currentTime: currentTime)
    }

    #if DEBUG
    override func didFinishUpdate() {
        driver.didFinishUpdate()
    }
    #endif

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        driver.touchesBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        driver.touchesMoved(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        driver.touchesEnded(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        driver.touchesEnded(touches, cancelled: true)
    }
}
