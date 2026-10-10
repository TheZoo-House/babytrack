import Foundation

public enum DeepLink: Equatable, Sendable {
    case log(String), openSleep(String), endSleep(String), record(String), join(String)

    public init?(url: URL) {
        guard url.scheme == "babytrack", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func value(_ name: String) -> String? {
            guard let value = components.queryItems?.first(where: { $0.name == name })?.value, !value.isEmpty, value.count <= 128 else { return nil }
            return value
        }
        switch url.host {
        case "feeding", "diaper": self = .log(url.host!)
        case "sleep": guard let id = value("session") else { return nil }; self = .openSleep(id)
        case "end-sleep": guard let id = value("session") else { return nil }; self = .endSleep(id)
        case "record":
            if let id = value("id") { self = .record(id) }
            else if let type = value("type"), Catalog.shared.types.contains(where: { $0.id == type && !["formula", "child"].contains(type) }) { self = .log(type) }
            else { return nil }
        case "join": guard let code = value("code") else { return nil }; self = .join(code)
        default: return nil
        }
    }

    public var url: URL {
        var components = URLComponents(); components.scheme = "babytrack"
        switch self {
        case let .log(type): components.host = "record"; components.queryItems = [.init(name: "type", value: type)]
        case let .openSleep(id): components.host = "sleep"; components.queryItems = [.init(name: "session", value: id)]
        case let .endSleep(id): components.host = "end-sleep"; components.queryItems = [.init(name: "session", value: id)]
        case let .record(id): components.host = "record"; components.queryItems = [.init(name: "id", value: id)]
        case let .join(code): components.host = "join"; components.queryItems = [.init(name: "code", value: code)]
        }
        return components.url!
    }
}
