import Foundation

/// Loads gameplay tuning JSON. All gameplay numbers live in `Tuning/*.json` resources,
/// never hard-coded (docs/PLAN.md §10). Debug builds can hot-reload later (issue F4).
public enum Tuning {
    public enum LoadError: Error { case missing(String) }

    public static func load<T: Decodable>(_ type: T.Type, named name: String, in bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.missing(name)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
