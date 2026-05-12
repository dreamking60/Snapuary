import Foundation

enum PendingAppRoute: Codable, Equatable {
    case orbit(String)
    case recipe(String)
    case latestScreenshots
}

struct AppRouteStore {
    private enum Keys {
        static let pendingRoute = "pendingAppRoute"
    }

    private let userDefaults: UserDefaults
    static let shared = AppRouteStore()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func setPendingRoute(_ route: PendingAppRoute) {
        guard let data = try? JSONEncoder().encode(route) else {
            return
        }
        userDefaults.set(data, forKey: Keys.pendingRoute)
    }

    func consumePendingRoute() -> PendingAppRoute? {
        guard let data = userDefaults.data(forKey: Keys.pendingRoute),
              let route = try? JSONDecoder().decode(PendingAppRoute.self, from: data) else {
            return nil
        }
        userDefaults.removeObject(forKey: Keys.pendingRoute)
        return route
    }
}
