import Foundation
import Security
import CryptoKit

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case live, vod, series
    var id: String { rawValue }
    var title: String { self == .live ? "TV ao vivo" : self == .vod ? "Filmes" : "Séries" }
    var icon: String { self == .live ? "tv" : self == .vod ? "film" : "rectangle.stack" }
}
struct Credentials: Codable {
    var server: String; var user: String; var password: String
    var account: String { SHA256.hash(data: Data((server + "|" + user).utf8)).map { String(format: "%02x", $0) }.joined() }
    func validated() throws -> Credentials {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/player_api.php") { s = String(s.dropLast(15)) }
        guard let url = URLComponents(string: s), ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, !user.isEmpty, !password.isEmpty else { throw AppError.invalidServer }
        return Credentials(server: s, user: user, password: password)
    }
}
enum AppError: LocalizedError {
    case invalidServer, access, response
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Informe servidor HTTP/HTTPS, usuário e senha válidos."
        case .access: return "Acesso recusado. Confira os dados e a validade da conta."
        case .response: return "Não foi possível acessar o serviço. Confira a conexão e tente novamente."
        }
    }
}
struct Media: Codable, Identifiable, Hashable {
    let streamID: String; let title: String; let kind: MediaKind
    var image: String = ""; var category: String = ""; var ext: String = "mp4"
    var season: Int?; var episode: Int?; var summary: String = ""; var added: Double = 0
    var id: String { "\(kind.rawValue):\(streamID):\(episode != nil)" }
}
struct Category: Identifiable { var id: String; var title: String }
struct Catalog { var entries: [Media]; var categories: [Category] }
struct ViewingData: Codable {
    var favorites: [Media] = []; var recent: [Media] = []; var progress: [String: Double] = [:]
}
enum Vault {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "GIPTV.iOS", kSecAttrAccount as String: "access"]
    static func read() -> Credentials? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }
    static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AppError.response }
        } else if status != errSecSuccess { throw AppError.response }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct Xtream {
    let credentials: Credentials
    static let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    static func string(_ d: [String: Any], _ key: String, fallback: String = "") -> String {
        guard let v = d[key], !(v is NSNull) else { return fallback }
        return String(describing: v)
    }
    func request(_ action: String? = nil, parameter: (String, String)? = nil) async throws -> Any {
        guard var c = URLComponents(string: credentials.server + "/player_api.php") else { throw AppError.invalidServer }
        c.queryItems = [URLQueryItem(name: "username", value: credentials.user), URLQueryItem(name: "password", value: credentials.password)]
        if let action { c.queryItems?.append(URLQueryItem(name: "action", value: action)) }
        if let parameter { c.queryItems?.append(URLQueryItem(name: parameter.0, value: parameter.1)) }
        guard let url = c.url else { throw AppError.invalidServer }
        var r = URLRequest(url: url); r.timeoutInterval = 30
        let (data, response) = try await Self.session.data(for: r)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 64 * 1024 * 1024 else { throw AppError.response }
        return try JSONSerialization.jsonObject(with: data)
    }
    func login() async throws {
        guard let r = try await request() as? [String: Any], let u = r["user_info"] as? [String: Any], Self.string(u, "auth") == "1", Self.string(u, "status", fallback: "Active").lowercased() == "active" else { throw AppError.access }
    }
    func catalog(_ kind: MediaKind) async throws -> Catalog {
        let raw = try await request(kind == .series ? "get_series" : "get_\(kind.rawValue)_streams")
        let groups = try await request("get_\(kind.rawValue)_categories")
        guard let rows = raw as? [[String: Any]], let cats = groups as? [[String: Any]] else { throw AppError.response }
        var seen = Set<String>()
        let entries = rows.compactMap { d -> Media? in
            let id = Self.string(d, kind == .series ? "series_id" : "stream_id")
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return Media(streamID: id, title: Self.string(d, "name", fallback: "Sem título"), kind: kind,
                image: Self.string(d, kind == .series ? "cover" : "stream_icon"), category: Self.string(d, "category_id"),
                ext: Self.string(d, "container_extension", fallback: "mp4"), summary: Self.string(d, "plot"), added: Double(Self.string(d, "added")) ?? 0)
        }
        return Catalog(entries: entries, categories: cats.map { Category(id: Self.string($0, "category_id"), title: Self.string($0, "category_name")) })
    }
    func episodes(_ series: Media) async throws -> [Media] {
        guard let r = try await request("get_series_info", parameter: ("series_id", series.streamID)) as? [String: Any], let seasons = r["episodes"] as? [String: Any] else { throw AppError.response }
        var result: [Media] = []
        for (s, value) in seasons {
            for e in value as? [[String: Any]] ?? [] {
                let info = e["info"] as? [String: Any] ?? [:]
                let number = Int(Self.string(e, "episode_num")) ?? 0
                let id = Self.string(e, "id"); if id.isEmpty { continue }
                result.append(Media(streamID: id, title: "E\(number) · " + Self.string(e, "title", fallback: series.title), kind: .series,
                    image: series.image, ext: Self.string(e, "container_extension", fallback: "mp4"), season: Int(s) ?? 0,
                    episode: number, summary: Self.string(info, "plot", fallback: series.summary)))
            }
        }
        return result.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }
    func guide(_ media: Media) async throws -> [String] {
        guard let r = try await request("get_short_epg", parameter: ("stream_id", media.streamID)) as? [String: Any] else { return [] }
        return (r["epg_listings"] as? [[String: Any]] ?? []).prefix(8).map { row in
            let title = Self.string(row, "title")
            let decoded = Data(base64Encoded: title).flatMap { String(data: $0, encoding: .utf8) } ?? title
            return Self.string(row, "start") + " · " + decoded
        }
    }
    func stream(_ media: Media) throws -> URL {
        let path = media.kind == .vod ? "movie" : media.kind.rawValue
        let ext = media.kind == .live ? "m3u8" : media.ext
        guard ext.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil, var url = URL(string: credentials.server) else { throw AppError.response }
        for part in [path, credentials.user, credentials.password, media.streamID + "." + ext] { url.appendPathComponent(part) }
        return url
    }
}
