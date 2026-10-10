import Foundation
import NetDiagCore

/// DNS resolution via the system resolver (`getaddrinfo`).
///
/// Using `getaddrinfo` rather than rolling a hand-written UDP query has one
/// important consequence: the lookup goes through whatever resolver the system
/// has configured, including any DNS settings a tunnel has installed. A
/// hand-rolled UDP query would bypass that and could return a different answer
/// from the one the rest of the device would get, which would make the whole
/// report misleading.
///
/// This type sends no traffic of its own and reads no other application's
/// queries. It is the same lookup any HTTP client performs.
public struct SystemDNSResolver: DNSResolving {

    private let queue = DispatchQueue(label: "netdiag.dns", qos: .utility)

    public init() {}

    public func resolve(host: String, timeout: TimeInterval) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in

            // `getaddrinfo` is a blocking C call with no timeout parameter.
            // Whichever of "work finished" or "deadline reached" happens first
            // wins; the loser is discarded so a late answer cannot resume the
            // continuation a second time.
            let settled = ResumeGate()

            queue.async { [queue] in
                do {
                    let addresses = try Self.lookup(host: host)
                    settled.resumeOnce { continuation.resume(returning: addresses) }
                } catch {
                    settled.resumeOnce { continuation.resume(throwing: error) }
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                settled.resumeOnce {
                    continuation.resume(throwing: ProbeError.timedOut(stage: .dns))
                }
            }

            _ = queue  // keeps the queue captured for clarity
        }
    }

    /// Synchronous lookup. Blocking; always called on `queue`.
    private static func lookup(host: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            // SOCK_STREAM/TCP matches what an HTTPS connection would ask for,
            // so the answer reflects a path this tool could actually use.
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &resultPointer)
        guard status == 0 else {
            throw ProbeError.posix(code: status, stage: .dns)
        }
        defer { if let resultPointer { freeaddrinfo(resultPointer) } }

        var addresses: [String] = []
        var seen = Set<String>()
        var cursor: UnsafeMutablePointer<addrinfo>? = resultPointer

        while let node = cursor?.pointee {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let name = getnameinfo(
                node.ai_addr,
                node.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if name == 0 {
                let text = String(cString: buffer)
                if seen.insert(text).inserted {
                    addresses.append(text)
                }
            }
            cursor = node.ai_next
        }

        return addresses
    }
}

/// Runs a body exactly once, no matter how many racers reach it.
///
/// `withCheckedThrowingContinuation` must be resumed exactly once; a
/// double-resume traps. This makes the race above safe.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        if used {
            lock.unlock()
            return
        }
        used = true
        lock.unlock()
        body()
    }
}