import CBCore
import Foundation

extension RatingCurves {
    /// Loads `Tuning/ratings.json` shipped with CBSim; falls back to `.default`.
    public static func loadBundled() -> RatingCurves {
        (try? Tuning.load(RatingCurves.self, named: "ratings", in: .module)) ?? .default
    }
}
