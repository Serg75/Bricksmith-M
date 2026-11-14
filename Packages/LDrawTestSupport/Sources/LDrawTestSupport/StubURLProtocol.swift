//
//  StubURLProtocol.swift
//  LDrawTestSupport
//
//  A URL protocol that answers requests without a network.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Foundation

/// Answers every request with what `handler` returns, and keeps the requests.
/// The handler and the requests are process-wide, so suites that use it run
/// their tests one at a time.
public final class StubURLProtocol: URLProtocol {

    public struct Reply {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    public static func answer(with handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        Self.handler = handler
        seen = []
    }

    public static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        let reply = handler?(request) ?? Reply(status: 500)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}
}
