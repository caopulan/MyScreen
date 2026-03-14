import Foundation

struct WallSessionSnapshot: Codable, Equatable {
    var selectedSources: [MonitorSource]
    var focusedSourceID: String?
    var windowSize: CodableSize
    var preferredColumnCount: Int?

    static let empty = WallSessionSnapshot(
        selectedSources: [],
        focusedSourceID: nil,
        windowSize: CodableSize(width: 1440, height: 900),
        preferredColumnCount: nil
    )
}

final class WallSessionSnapshotStore {
    private let userDefaults: UserDefaults
    private let key = "myscreen.wall-session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> WallSessionSnapshot? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(WallSessionSnapshot.self, from: data)
    }

    func save(_ snapshot: WallSessionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}
