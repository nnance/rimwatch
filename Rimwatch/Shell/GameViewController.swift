import GameCore
import SpriteKit
import UIKit

/// Hosts the SpriteKit view and applies the fold pose: landscape while open, portrait while
/// closed, and (DEBUG override only) a letterbox at the Duo inner display's aspect so the game can
/// be tried on an ordinary phone. The scene resizes with the view, so nothing assumes a size.
final class GameViewController: UIViewController {
    /// The Duo inner display's aspect, width over height, when open (about 890 x 626 pt).
    static let innerDisplayAspect: CGFloat = 890.0 / 626.0
    /// Fallback crease band, as a fraction of the width, when the SDK reports no division region.
    private static let fallbackCreaseFraction: CGFloat = 0.05

    private let skView = SKView()
    private var scene: ShellScene?
    private let foldGate = FoldGate()
    private var lastLoggedRegions = ""

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .black
        skView.isMultipleTouchEnabled = true
        skView.preferredFramesPerSecond = 120
        skView.ignoresSiblingOrder = true
        skView.backgroundColor = .black
        #if DEBUG
        // Launch with -showStats to see the frame rate and node count (debug builds only).
        if ProcessInfo.processInfo.arguments.contains("-showStats") {
            skView.showsFPS = true
            skView.showsNodeCount = true
            skView.showsDrawCount = true
        }
        #endif
        root.addSubview(skView)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        foldGate.onChange = { [weak self] pose in self?.poseChanged(pose) }
        foldGate.start(observing: view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        skView.frame = playfieldFrame(in: view.bounds)
        guard skView.bounds.width > 0, skView.bounds.height > 0 else { return }
        if scene == nil {
            let scene = ShellScene(size: skView.bounds.size, entry: ModeRegistry.launch)
            scene.scaleMode = .resizeFill
            scene.safeAreaInsets = layoutInsets()
            skView.presentScene(scene)
            self.scene = scene
            if let pose = foldGate.pose { scene.setPose(pose) }
        }
        scene?.safeAreaInsets = layoutInsets()
        scene?.keepClear = creaseBand()
        #if DEBUG
        let layout = "view \(view.bounds.size) skView \(skView.frame) safe \(skView.safeAreaInsets) scene \(scene?.size ?? .zero) screen \(view.window?.screen.bounds.size ?? .zero) occlusion \(skView.reservedRegions(kind: .occlusion, options: .includeInactive).map { "\($0.frame) active \($0.isActive)" }) division \(skView.reservedRegions(kind: .division, options: .includeInactive).map { "\($0.frame) active \($0.isActive)" }) orientation \(view.window?.windowScene?.effectiveGeometry.interfaceOrientation.rawValue ?? -1)"
        if layout != lastLoggedLayout {
            lastLoggedLayout = layout
            NSLog("[Rimwatch layout] %@", layout)
        }
        #endif
    }

    #if DEBUG
    private var lastLoggedLayout = ""
    #endif

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    func appWillResignActive() {
        scene?.appWillResignActive()
    }

    // MARK: Fold

    private func poseChanged(_ pose: FoldPose) {
        debugLog("[Rimwatch fold] pose \(pose) (overridden: \(foldGate.isOverridden ? "yes" : "no"))")
        setNeedsUpdateOfSupportedInterfaceOrientations()
        view.setNeedsLayout()
        scene?.setPose(pose)
    }

    /// Letterboxed only for the DEBUG override while open, which stands in for the inner display
    /// on phones that don't have one.
    private var isLetterboxed: Bool {
        foldGate.isOverridden && foldGate.pose == .open
    }

    private func playfieldFrame(in bounds: CGRect) -> CGRect {
        guard isLetterboxed, bounds.width > 0, bounds.height > 0 else { return bounds }
        // Fit inside the safe area so a notch or island doesn't cover the letterboxed game.
        let safe = bounds.inset(by: view.safeAreaInsets)
        let aspect = Self.innerDisplayAspect
        var size = CGSize(width: safe.width, height: safe.width / aspect)
        if size.height > safe.height { size = CGSize(width: safe.height * aspect, height: safe.height) }
        return CGRect(x: (safe.midX - size.width / 2).rounded(), y: (safe.midY - size.height / 2).rounded(),
                      width: size.width.rounded(), height: size.height.rounded())
    }

    /// The safe area, refined with UIKit's occlusion reserved regions. A camera hole in a top
    /// corner shows up as a full-height side inset (84 pt on the Duo's outer display); content only
    /// has to clear the hole itself, so such an inset is traded for a top inset just below the hole.
    private func layoutInsets() -> UIEdgeInsets {
        var insets = skView.safeAreaInsets
        let bounds = skView.bounds
        guard bounds.width > 0 else { return insets }
        let holes = skView.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            .filter { $0.minY <= 1 && $0.maxY < bounds.height * 0.25 }
        func explained(_ inset: CGFloat, _ edgeHole: (CGRect) -> Bool) -> CGRect? {
            guard inset > 0 else { return nil }
            return holes.first { edgeHole($0) && abs($0.width - inset) < 2 }
        }
        if let hole = explained(insets.right, { abs($0.maxX - bounds.width) < 1 }) {
            insets.right = 0
            insets.top = max(insets.top, hole.maxY)
        }
        if let hole = explained(insets.left, { $0.minX < 1 }) {
            insets.left = 0
            insets.top = max(insets.top, hole.maxY)
        }
        return insets
    }

    /// The crease, as an x range in scene (= view) points, while open in landscape. Uses UIKit's
    /// division reserved regions when there are any; otherwise a band down the middle.
    private func creaseBand() -> ClosedRange<CGFloat>? {
        guard foldGate.pose == .open, skView.bounds.width > skView.bounds.height else { return nil }
        let regions = skView.reservedRegions(kind: .division).filter(\.isActive)
        let description = regions.map { "\($0.frame) margins \($0.margins)" }.joined(separator: "; ")
        if description != lastLoggedRegions {
            lastLoggedRegions = description
            debugLog("[Rimwatch fold] division reserved regions: \(regions.isEmpty ? "none" : description)")
        }
        // A vertical division region (taller than wide) is the crease.
        let vertical = regions.map(\.frame).filter { $0.height >= $0.width }
        if let first = vertical.first {
            let union = vertical.dropFirst().reduce(first) { $0.union($1) }
            if union.width > 0 { return union.minX...union.maxX }
        }
        let half = max(12, skView.bounds.width * Self.fallbackCreaseFraction / 2)
        let mid = skView.bounds.midX
        return (mid - half)...(mid + half)
    }

    // MARK: Orientation and chrome

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch foldGate.pose {
        case .open: .landscape
        case .closed, .noHinge: .portrait
        case nil: .allButUpsideDown
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    // Thumbs live near the bottom edge; make the system ask twice before taking a swipe there.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
