import GameCore
import SpriteKit
import UIKit

/// What a mode can ask of the shell.
@MainActor
final class ShellServices {
    let factory: GlowShapeFactory
    let style: ShellStyle
    /// Game time in seconds, advanced by the shell each frame.
    var clock: TimeInterval = 0
    /// The scene's geometry, refreshed by the shell before every layout.
    private(set) var geometry = ShellGeometry(size: .zero, safeArea: .zero, keepClear: nil, screenScale: 2)
    weak var scene: ShellScene?

    init(factory: GlowShapeFactory, style: ShellStyle) {
        self.factory = factory
        self.style = style
    }

    func refreshGeometry() {
        guard let scene else { return }
        geometry = ShellGeometry(size: scene.size, safeArea: scene.safeAreaInsets, keepClear: scene.keepClear,
                                 screenScale: scene.view?.contentScaleFactor ?? 2)
    }
}
