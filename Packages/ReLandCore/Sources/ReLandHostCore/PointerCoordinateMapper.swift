import CoreGraphics

enum PointerCoordinateMapper {
    static func absolutePoint(
        x: Double,
        y: Double,
        in bounds: CGRect
    ) -> CGPoint {
        let normalizedX = min(max(x, 0), 1)
        let normalizedY = min(max(y, 0), 1)
        let usableWidth = max(bounds.width - 1, 0)
        let usableHeight = max(bounds.height - 1, 0)
        return CGPoint(
            x: bounds.minX + usableWidth * normalizedX,
            y: bounds.minY + usableHeight * normalizedY
        )
    }
}
