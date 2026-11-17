import Foundation

/// Info-level logging for simulator checks. Compiled out of Release builds; real failures still
/// use NSLog directly.
@inline(__always)
nonisolated func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}
