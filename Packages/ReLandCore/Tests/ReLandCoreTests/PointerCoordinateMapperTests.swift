import CoreGraphics
import Testing
@testable import ReLandHostCore

struct PointerCoordinateMapperTests {
    @Test
    func mapsNormalizedEdgesInsideDisplayBounds() {
        let bounds = CGRect(x: 100, y: 50, width: 1_440, height: 900)

        #expect(
            PointerCoordinateMapper.absolutePoint(
                x: 0,
                y: 0,
                in: bounds
            ) == CGPoint(x: 100, y: 50)
        )
        #expect(
            PointerCoordinateMapper.absolutePoint(
                x: 1,
                y: 1,
                in: bounds
            ) == CGPoint(x: 1_539, y: 949)
        )
    }

    @Test
    func clampsOutOfRangeCoordinates() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)

        #expect(
            PointerCoordinateMapper.absolutePoint(
                x: -1,
                y: 2,
                in: bounds
            ) == CGPoint(x: 0, y: 49)
        )
    }
}
