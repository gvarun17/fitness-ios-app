import Foundation

/// An activity summary from the Garmin Connect Personal API activity search.
public struct GarminActivity: Decodable, Equatable, Sendable {
    public struct ActivityType: Decodable, Equatable, Sendable {
        public var typeKey: String?
    }

    public var activityId: Int64
    public var activityName: String?
    /// "yyyy-MM-dd HH:mm:ss" in UTC.
    public var startTimeGMT: String?
    /// Milliseconds since the Unix epoch.
    public var beginTimestamp: Int64?
    /// Meters.
    public var distance: Double?
    /// Seconds.
    public var duration: Double?
    public var activityType: ActivityType?

    public var startDate: Date? {
        if let beginTimestamp { return Date(timeIntervalSince1970: Double(beginTimestamp) / 1000) }
        guard let startTimeGMT else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: startTimeGMT)
    }
}

/// Request building and response parsing for the Garmin Connect Personal API.
/// Paths and parameters follow Garmin's published API reference.
public enum GarminAPI {
    public static let host = "personal.connectapi.garmin.com"
    public static let keyPageURL = "https://connect.garmin.com/app/settings/personalApiToken"

    private static func url(path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    /// POST with `Authorization: ApiKey <key>` to exchange the personal key for an access token.
    public static var tokenURL: URL {
        url(path: "/personalapitoken-service/personal-api/personal-api-key/token")
    }

    /// Running activities, oldest first, optionally limited to those on or after `since`.
    public static func activitiesURL(start: Int, limit: Int, since: Date? = nil) -> URL {
        var query = [
            URLQueryItem(name: "activityType", value: "running"),
            URLQueryItem(name: "sortOrder", value: "asc"),
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let since {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            query.append(URLQueryItem(name: "startDate", value: formatter.string(from: since)))
        }
        return url(path: "/activitylist-service/activities/search/activities", query: query)
    }

    /// The activity's original file, delivered as a ZIP archive.
    public static func downloadURL(activityID: Int64) -> URL {
        url(path: "/download-service/files/activity/\(activityID)")
    }

    /// Pulls the access token out of the token response, accepting the usual OAuth2
    /// field name and close variants, or a bare token string.
    public static func parseToken(_ data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["access_token", "accessToken", "token"] {
                if let token = object[key] as? String, !token.isEmpty { return token }
            }
            return nil
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t")),
              !text.isEmpty, !text.contains(" "), !text.hasPrefix("{"), !text.hasPrefix("<") else { return nil }
        return text
    }

    public static func parseActivities(_ data: Data) throws -> [GarminActivity] {
        try JSONDecoder().decode([GarminActivity].self, from: data)
    }

    /// Stable identifier stored on an imported run so it is never imported twice.
    public static func externalID(activityID: Int64) -> String {
        "garmin:\(activityID)"
    }
}
