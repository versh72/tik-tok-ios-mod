import Foundation

/// A single user-supplied endpoint that the app will probe.
///
/// The tool never guesses TikTok endpoints and never touches TikTok traffic.
/// Every target is entered by the person running the diagnostic, or picked
/// from the built-in list of well-known public reference endpoints.
public struct ProbeTarget: Identifiable, Hashable, Codable, Sendable {

    public let id: UUID
    /// Human label shown in the UI. Never sent anywhere.
    public var label: String
    /// Host name that will be resolved and connected to.
    public var host: String
    /// Port. Defaults to 443.
    public var port: UInt16
    /// Optional path used for the HTTPS request.
    public var path: String
    /// Grouping tag used to compare runs, e.g. "VPN on" / "VPN off".
    public var scenario: String
    /// Optional note. Redacted on export.
    public var note: String

    public init(
        id: UUID = UUID(),
        label: String,
        host: String,
        port: UInt16 = 443,
        path: String = "/",
        scenario: String = "",
        note: String = ""
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.path = path
        self.scenario = scenario
        self.note = note
    }

    /// `host:port` as displayed in result rows.
    public var authority: String {
        port == 443 ? host : "\(host):\(port)"
    }

    /// The URL used by the HTTPS probe. Built from validated components only.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port == 443 ? nil : Int(port)
        components.path = path.isEmpty ? "/" : path
        return components.url
    }
}