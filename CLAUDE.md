# Rimwatch

An original side-scrolling rescue shooter for the iPhone Duo's inner display. Native iOS, Swift,
SpriteKit, no third-party dependencies, no asset files (art drawn in code, sound synthesised).

## Start here

Read `PLAN.md`. Its **Progress** checklist says what is done. Continue from the first unticked item,
and tick items as they are built and verified.

## Rules

- This is an original game. Do not copy the name, sprites, sounds, enemy names or screen layout of
  any existing game.
- Gameplay only runs on the open inner display. When the phone is closed the game pauses and the
  outer display shows the pause menu (start over, end game, options, high scores). See
  "Fold behaviour" in `PLAN.md`.
- `GameCore/` is a plain Swift package with no UIKit or SpriteKit imports. It knows entity roles,
  never their appearance; appearance comes from a `Theme`.

## Building and testing

- Game logic: `swift test` inside `GameCore/`. Works with Xcode closed. The tests use Swift
  Testing, which the Command Line Tools alone don't provide. If `import Testing` fails, run
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, or switch `xcode-select`
  to Xcode.
- `#expect` cannot wrap a mutating call. Write `#expect(session.resume() == true)`, not
  `#expect(session.resume())`.
- The app drives `GameSession` (never `Simulation` directly) and reacts to the `GameEvent`s it
  returns. Gameplay numbers live in `GameCore/Sources/GameCore/Tuning.swift`.
- The app: build, run and test through the Xcode MCP server (`xcode`, added with
  `claude mcp add --transport stdio xcode -- xcrun mcpbridge`). The project must be open in Xcode.
  If the `xcode` tools are missing, check `claude mcp list` and the "Prerequisites" in `PLAN.md`
  before falling back to `xcodebuild`.
- The iPhone Duo SDK and simulator need Xcode 27.1 or later. The Duo API names in `PLAN.md` are
  secondhand; confirm them against the installed SDK before using them.
