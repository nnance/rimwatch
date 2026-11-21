/// The only look the shared screens (menus, pause button, countdown) need: a few colours and the
/// menu sounds. A mode's theme supplies it.
public struct ShellStyle: Sendable, Equatable {
    public var background: RGB
    /// Menu text.
    public var text: RGB
    /// The selected menu item.
    public var highlight: RGB
    /// Menu headings.
    public var heading: RGB
    /// The pause button.
    public var controls: RGB
    public var menuSounds: [MenuSound: SoundPatch]

    public init(background: RGB, text: RGB, highlight: RGB, heading: RGB, controls: RGB,
                menuSounds: [MenuSound: SoundPatch] = [:]) {
        self.background = background
        self.text = text
        self.highlight = highlight
        self.heading = heading
        self.controls = controls
        self.menuSounds = menuSounds
    }
}
