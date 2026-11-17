import CoreHaptics
import Foundation
import GameController
import GameCore

/// The game controller, read into `GameCore`'s device-neutral `PadReader`. This file only
/// translates `GCController` state into `PadSnapshot`s and follows controllers coming and going;
/// the dead zone, button layout, press latching and menu repeat all live in `GameCore`.
///
/// One controller is used at a time: the system's current one if it is an extended gamepad,
/// otherwise the first extended gamepad connected. A controller already connected at launch is
/// picked up by `start()`. In DEBUG builds a simulated controller (driven by Darwin
/// notifications, see `DebugPadCommands`) takes the place of a real one while it is connected.
final class GamepadInput {
    enum Change {
        /// A controller became the active one. `replaced` is true when it took over from another.
        case connected(name: String, replaced: Bool)
        case disconnected(name: String)
    }

    /// Told when the active controller changes.
    var onChange: ((Change) -> Void)?

    /// Presses, held buttons and menu repeat for the active controller.
    var reader = PadReader()

    /// True while a controller (real or simulated) is the active one.
    var isConnected: Bool { source != nil }

    /// Haptics for the active controller, if it has any.
    private(set) var haptics: CoreHapticPlayer?

    private enum Source: Equatable {
        case real(GCController)
        #if DEBUG
        case simulated
        #endif

        var name: String {
            switch self {
            case .real(let controller):
                controller.vendorName ?? controller.productCategory
            #if DEBUG
            case .simulated:
                "Simulated controller"
            #endif
            }
        }
    }

    private var source: Source?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var simulatedState = PadSnapshot.neutral
    private var isSimulatedConnected = false
    #endif

    func start() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect,
                     .GCControllerDidBecomeCurrent, .GCControllerDidStopBeingCurrent] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.chooseController() }
            })
        }
        #if DEBUG
        DebugPadCommands.listen(self)
        #endif
        // Picks up a controller that was connected before launch.
        chooseController()
    }

    /// Re-reads the active controller, in case a change slipped past its handlers. Cheap.
    func poll() {
        guard case .real(let controller) = source, let pad = controller.extendedGamepad else { return }
        // Compared field by field, so a frame where nothing changed builds no snapshot (and no Set).
        let current = reader.current
        let unchanged = pad.buttonA.isPressed == current.isDown(.a) && pad.buttonB.isPressed == current.isDown(.b)
            && pad.buttonX.isPressed == current.isDown(.x) && pad.buttonY.isPressed == current.isDown(.y)
            && pad.buttonMenu.isPressed == current.isDown(.menu)
            && Double(pad.leftThumbstick.xAxis.value) == current.stick.x
            && Double(pad.leftThumbstick.yAxis.value) == current.stick.y
            && Double(pad.dpad.xAxis.value) == current.dpad.x && Double(pad.dpad.yAxis.value) == current.dpad.y
        if !unchanged { reader.receive(Self.snapshot(pad)) }
    }

    // MARK: Choosing a controller

    private func chooseController() {
        #if DEBUG
        if isSimulatedConnected {
            switchTo(.simulated)
            return
        }
        #endif
        // A snapshot controller is a recording of state, not a device.
        var candidates = GCController.controllers().filter { $0.extendedGamepad != nil && !$0.isSnapshot }
        #if DEBUG
        let described = GCController.controllers().map {
            "\($0.vendorName ?? "nil")/\($0.productCategory) attached \($0.isAttachedToDevice) snapshot \($0.isSnapshot) extended \($0.extendedGamepad != nil) current \($0 === GCController.current)"
        }
        NSLog("[Rimwatch pad] controllers: %@", described.joined(separator: "; "))
        #endif
        #if DEBUG && targetEnvironment(simulator)
        // The simulator presents a "Gamepad" (MFi) controller even with none attached, which
        // would hide the touch controls on every launch. Ignore real controllers there unless
        // launched with -realPads; the simulated controller stands in for them.
        if !ProcessInfo.processInfo.arguments.contains("-realPads") { candidates = [] }
        #endif
        let next: GCController?
        if let current = GCController.current, candidates.contains(where: { $0 === current }) {
            next = current
        } else if case .real(let active) = source, candidates.contains(where: { $0 === active }) {
            next = active
        } else {
            next = candidates.first
        }
        switchTo(next.map(Source.real))
    }

    private func switchTo(_ next: Source?) {
        guard next != source else { return }
        let previous = source
        if case .real(let old) = previous {
            old.extendedGamepad?.valueChangedHandler = nil
        }
        source = next
        reader.reset()
        haptics = nil
        switch next {
        case .real(let controller):
            controller.handlerQueue = .main
            controller.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
                MainActor.assumeIsolated {
                    let snapshot = Self.snapshot(pad)
                    self?.reader.receive(snapshot)
                }
            }
            haptics = CoreHapticPlayer.controller { controller.haptics?.createEngine(withLocality: .default) }
            if let pad = controller.extendedGamepad { reader.receive(Self.snapshot(pad)) }
        #if DEBUG
        case .simulated:
            reader.receive(simulatedState)
        #endif
        case nil:
            break
        }
        debugLog("[Rimwatch pad] active controller: \(next?.name ?? "none") (haptics: \(haptics == nil ? "no" : "yes"))")
        if let next {
            onChange?(.connected(name: next.name, replaced: previous != nil))
        } else if let previous {
            onChange?(.disconnected(name: previous.name))
        }
    }

    /// One reading of an extended gamepad.
    private static func snapshot(_ pad: GCExtendedGamepad) -> PadSnapshot {
        var buttons: Set<PadButton> = []
        if pad.buttonA.isPressed { buttons.insert(.a) }
        if pad.buttonB.isPressed { buttons.insert(.b) }
        if pad.buttonX.isPressed { buttons.insert(.x) }
        if pad.buttonY.isPressed { buttons.insert(.y) }
        if pad.buttonMenu.isPressed { buttons.insert(.menu) }
        return PadSnapshot(
            stick: Vec2(Double(pad.leftThumbstick.xAxis.value), Double(pad.leftThumbstick.yAxis.value)),
            dpad: Vec2(Double(pad.dpad.xAxis.value), Double(pad.dpad.yAxis.value)),
            buttons: buttons
        )
    }

    // MARK: Simulated controller (DEBUG)

    #if DEBUG
    func simulatedConnect() {
        isSimulatedConnected = true
        simulatedState = .neutral
        chooseController()
    }

    func simulatedDisconnect() {
        isSimulatedConnected = false
        simulatedState = .neutral
        if source == .simulated { switchTo(nil) }
        chooseController()
    }

    /// Changes the simulated controller's state, as its handlers would for a real one.
    func simulated(_ change: (inout PadSnapshot) -> Void) {
        guard isSimulatedConnected else {
            NSLog("[Rimwatch pad] simulated controller is not connected; ignored")
            return
        }
        change(&simulatedState)
        if source == .simulated { reader.receive(simulatedState) }
    }
    #endif
}
