import GameCore
import UIKit

nonisolated extension RGB {
    func uiColor(alpha: Double = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    func cgColor(alpha: Double = 1) -> CGColor {
        uiColor(alpha: alpha).cgColor
    }
}
