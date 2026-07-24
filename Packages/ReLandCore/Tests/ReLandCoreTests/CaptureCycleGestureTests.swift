import CoreGraphics
import Testing
@testable import ReLandCore

struct CaptureCycleGestureTests {
    @Test
    func classifiesHorizontalThreeFingerSwipes() {
        #expect(
            CaptureCycleGestureClassifier.direction(
                translation: CGSize(width: -100, height: 12),
                horizontalVelocity: -400
            ) == .next
        )
        #expect(
            CaptureCycleGestureClassifier.direction(
                translation: CGSize(width: 100, height: -12),
                horizontalVelocity: 400
            ) == .previous
        )
    }

    @Test
    func rejectsShortSlowOrVerticalGestures() {
        #expect(
            CaptureCycleGestureClassifier.direction(
                translation: CGSize(width: 40, height: 0),
                horizontalVelocity: 400
            ) == nil
        )
        #expect(
            CaptureCycleGestureClassifier.direction(
                translation: CGSize(width: 100, height: 0),
                horizontalVelocity: 50
            ) == nil
        )
        #expect(
            CaptureCycleGestureClassifier.direction(
                translation: CGSize(width: 100, height: 90),
                horizontalVelocity: 400
            ) == nil
        )
    }
}
