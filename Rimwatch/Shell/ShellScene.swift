import GameCore
import SpriteKit
import UIKit

/// The one SpriteKit scene. It hands the frame, the touches, the fold pose and its geometry to
/// the loaded mode's driver, which runs the screen flow and the mode. It owns the devices every
/// mode shares, and swaps one mode's driver for another's when the title asks for a switch.
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
    private let devices: ShellDevices
    private let entries: [ModeRegistry.Entry]
    private var driver: any ModeDriver
    /// The fold gate's last verdict, handed to a newly loaded mode.
    private var pose: FoldPose?
    /// A mode the title asked to switch to, loaded at the start of the next frame (not in the
    /// middle of the old mode's touch or menu handling).
    private var pendingSwitch: ModeID?

    /// `entries` are every mode the title offers; `launch` is the one loaded first.
    init(size: CGSize, entries: [ModeRegistry.Entry], launch: ModeRegistry.Entry) {
        self.entries = entries
        services = ShellServices(factory: GlowShapeFactory(screenScale: 2), style: launch.style)
        devices = ShellDevices(options: Settings.shared.options)
        driver = launch.make(services, devices, entries.map(\.descriptor))
        super.init(size: size)
        services.scene = self
        backgroundColor = launch.style.background.uiColor()
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    private var isListening = false

    override func didMove(to view: SKView) {
        driver.attach()
        guard !isListening else { return }
        isListening = true
        devices.gamepad.onChange = { [weak self] change in self?.gamepadChanged(change) }
        devices.gamepad.start()
    }

    /// The fold gate's verdict. The first call reveals the game.
    func setPose(_ pose: FoldPose) {
        self.pose = pose
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
        if let id = pendingSwitch {
            pendingSwitch = nil
            switchMode(to: id)
        }
        driver.frame(currentTime: currentTime)
    }

    #if DEBUG
    override func didFinishUpdate() {
        driver.didFinishUpdate()
    }
    #endif

    // MARK: Modes

    /// The title chose another mode. It is loaded, and a run of it started, next frame.
    func requestModeSwitch(to id: ModeID) {
        pendingSwitch = id
    }

    /// Unloads the current mode and loads `id` in its place, then starts a run of it. The devices,
    /// clock, settings and pose carry over; the old mode's nodes and textures go.
    private func switchMode(to id: ModeID) {
        guard id != driver.descriptor.id, let entry = entries.first(where: { $0.descriptor.id == id }) else { return }
        debugLog("[Rimwatch mode] switching from \(driver.descriptor.id.rawValue) to \(id.rawValue)")
        driver.detach()
        services.factory.clear()
        services.style = entry.style
        backgroundColor = entry.style.background.uiColor()
        driver = entry.make(services, devices, entries.map(\.descriptor))
        driver.attach()
        if let pose { driver.setPose(pose) }
        driver.startRun()
    }

    private func gamepadChanged(_ change: GamepadInput.Change) {
        switch change {
        case .connected:
            devices.haptics.setController(connected: true, player: devices.gamepad.haptics)
        case .disconnected:
            devices.haptics.setController(connected: false, player: nil)
        }
        driver.gamepadChanged(change)
    }

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
