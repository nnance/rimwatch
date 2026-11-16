enum Collision {
    /// A point moves from the origin along `travel` during one step. Returns the fraction of the
    /// step (0...1) at which it first comes within `radius` of `center`, or nil if it never does.
    /// Sweeping like this stops fast shots from skipping over small targets between steps.
    static func sweepTime(center: Vec2, travel: Vec2, radius: Double) -> Double? {
        let c = center.x * center.x + center.y * center.y - radius * radius
        if c <= 0 { return 0 }
        let a = travel.x * travel.x + travel.y * travel.y
        if a == 0 { return nil }
        let b = -2 * (travel.x * center.x + travel.y * center.y)
        let discriminant = b * b - 4 * a * c
        if discriminant < 0 { return nil }
        let t = (-b - discriminant.squareRoot()) / (2 * a)
        return (0...1).contains(t) ? t : nil
    }
}
