import Foundation
import Network
import NetDiagCore

/// Wraps `NWPathMonitor` and publishes the current path.
///
/// What this can see, and what it cannot:
///
/// It can see the interface family (Wi-Fi, cellular, wired, loopback, other),
/// whether the path is marked expensive or constrained, and which IP families
/// it claims to support. All of that is public API usable by any app.
///
/// It cannot tell whether a VPN is running. `NEVPNManager` is gated behind the
/// Network Extension capability, which a free Apple Account does not grant, and
/// guessing from the interface type would be wrong often enough to mislead.
/// The tool therefore reports the path and says plainly that the VPN question
/// is outside what an ordinary app can observe.
public final class NetworkPathObserver: @unchecked Sendable {

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "netdiag.path", qos: .utility)
    private let lock = NSLock()
    private var snapshot: PathSnapshot

    /// Called on an unspecified queue whenever the path changes.
    private var onChange: (@Sendable (PathSnapshot) -> Void)?

    public init() {
        monitor = NWPathMonitor()
        snapshot = PathSnapshot()
    }

    public func start(onChange: @escaping @Sendable (PathSnapshot) -> Void) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next = Self.convert(path)

            self.lock.lock()
            self.snapshot = next
            let handler = self.onChange
            self.lock.unlock()

            handler?(next)
        }

        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    /// Most recent snapshot. Safe to call from any thread.
    public var current: PathSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    /// Blocks until the first path update arrives, or the deadline passes.
    ///
    /// Without this the first snapshot taken at launch is the default
    /// `.unknown`, and a report would claim an interface nobody observed.
    public func waitForFirstUpdate(timeout: TimeInterval = 2) async -> PathSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if current.interface != .unknown { return current }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return current
    }

    // MARK: - Conversion

    private static func convert(_ path: NWPath) -> PathSnapshot {
        PathSnapshot(
            interface: interface(from: path),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            supportsDNS: path.supportsDNS,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6,
            capturedAt: Date()
        )
    }

    private static func interface(from path: NWPath) -> PathSnapshot.Interface {
        if path.status != .satisfied { return .unknown }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        if path.usesInterfaceType(.loopback) { return .loopback }
        return .other
    }
}