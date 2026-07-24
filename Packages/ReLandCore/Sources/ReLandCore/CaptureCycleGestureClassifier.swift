import CoreGraphics
import Foundation

public enum CaptureCycleGestureClassifier {
    public static func direction(
        translation: CGSize,
        horizontalVelocity: CGFloat,
        minimumTranslation: CGFloat = 72,
        minimumVelocity: CGFloat = 120,
        horizontalDominanceRatio: CGFloat = 1.25
    ) -> CaptureCycleDirection? {
        guard
            abs(translation.width) >= minimumTranslation,
            abs(horizontalVelocity) >= minimumVelocity,
            abs(translation.width)
                > abs(translation.height)
                    * horizontalDominanceRatio
        else {
            return nil
        }
        return translation.width < 0 ? .next : .previous
    }
}
