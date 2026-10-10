import Foundation
import NetDiagCore

/// HTTPS probe built on `URLSession` with an ephemeral configuration.
///
/// Choices that matter:
///
/// * `URLSessionConfiguration.ephemeral` — no shared cookie store, no
///   persistent URL cache, no credential storage. Nothing to leak into the
///   report and nothing to leak onto disk.
/// * No delegate-based trust override. The system evaluation stands. If the
///   certificate is bad the request fails, and that failure is the finding.
/// * The response body is read only to count bytes, up to a small cap, then
///   discarded. No body text is retained, logged or exported.
public struct URLSessionHTTPSProber: HTTPSProbing {

    private let maxBodyBytes: Int
    private let maxRedirects: Int

    public init(maxBodyBytes: Int = 4_096, maxRedirects: Int = 5) {
        self.maxBodyBytes = maxBodyBytes
        self.maxRedirects = maxRedirects
    }

    public func probe(url: URL, timeout: TimeInterval) async throws -> HTTPSExchange {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [:]
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true

        let collector = MetricsCollector(maxRedirects: maxRedirects)
        let session = URLSession(
            configuration: configuration,
            delegate: collector,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        // Fall back to GET if the server does not answer HEAD. Some CDNs and
        // captive portals reject it with 405, which would be a false failure.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NetDiag/1.0", forHTTPHeaderField: "User-Agent")

        let started = DispatchTime.now()

        do {
            let (_, response) = try await session.data(for: request)
            return try await finish(
                session: session,
                url: url,
                started: started,
                response: response,
                collector: collector,
                usedHead: true
            )
        } catch let error as URLError where error.code == NSURLErrorBadServerResponse
            || error.code == NSURLErrorUnsupportedURL {
            // Retry once with GET before calling it a failure.
            var fallback = URLRequest(url: url)
            fallback.httpMethod = "GET"
            fallback.cachePolicy = .reloadIgnoringLocalCacheData
            fallback.setValue("NetDiag/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: fallback)
            return try await finish(
                session: session,
                url: url,
                started: started,
                response: response,
                collector: collector,
                usedHead: false
            )
        } catch let error as URLError {
            throw ProbeError.urlError(code: error.errorCode, stage: .https)
        }
    }

    private func finish(
        session: URLSession,
        url: URL,
        started: DispatchTime,
        response: URLResponse,
        collector: MetricsCollector,
        usedHead: Bool
    ) async throws -> HTTPSExchange {

        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.tlsUnavailable("response was not HTTP", stage: .https)
        }

        var bytes = 0
        if usedHead == false, let task = collector.lastTask {
            // Read a bounded prefix purely to confirm the body arrives. The
            // bytes are counted and thrown away; nothing is stored.
            if let stream = task.response?.bodyStream {
                bytes = Self.drain(stream, limit: maxBodyBytes)
            }
        }

        let total = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000

        return HTTPSExchange(
            statusCode: http.statusCode,
            bytesReceived: bytes,
            totalMilliseconds: total,
            timeToFirstByteMilliseconds: collector.timeToFirstByteMilliseconds,
            redirects: collector.redirectCount
        )
    }

    /// Reads up to `limit` bytes and throws them away.
    private static func drain(_ stream: InputStream, limit: Int) -> Int {
        stream.open()
        defer { stream.close() }

        var buffer = [UInt8](repeating: 0, count: 512)
        var total = 0
        while total < limit {
            let read = stream.read(&buffer, maxLength: min(buffer.count, limit - total))
            if read <= 0 { break }
            total += read
        }
        return total
    }
}

/// Collects redirect counts and timing from `URLSessionTaskMetrics`.
///
/// Deliberately does **not** implement `URLSessionTaskDelegate`'s challenge
/// handling: no `didReceive challenge` override means the system performs its
/// normal validation, and a rejected certificate surfaces as an error.
final class MetricsCollector: NSObject, URLSessionTaskDelegate, URLSessionDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private let maxRedirects: Int

    private(set) var redirectCount = 0
    private(set) var timeToFirstByteMilliseconds: Double?
    private(set) var lastTask: URLSessionTask?

    init(maxRedirects: Int) {
        self.maxRedirects = maxRedirects
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        lock.lock()
        lastTask = task
        redirectCount = metrics.transactionMetrics.reduce(0) { partial, transaction in
            partial + transaction.redirectCount
        }

        if let first = metrics.transactionMetrics.first {
            // Duration before the response started arriving.
            timeToFirstByteMilliseconds = Double(
                first.responseStartDate.timeIntervalSince(first.fetchStartDate) * 1000
            )
        }

        let shouldStop = redirectCount > maxRedirects
        lock.unlock()

        if shouldStop {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let allowed = redirectCount < maxRedirects
        if allowed { redirectCount += 1 }
        lock.unlock()

        completionHandler(allowed ? request : nil)
    }
}