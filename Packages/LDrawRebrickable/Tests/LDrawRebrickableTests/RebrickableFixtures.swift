//
//  RebrickableFixtures.swift
//  LDrawRebrickableTests
//
//  The fixture files, and a URL protocol that answers requests without a
//  network.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Foundation
import LDrawRebrickable
import zlib

enum RebrickableFixtures {

    static let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    /// The plain CSV files in Fixtures/downloads, gzipped as Rebrickable serves
    /// them, in a folder made once per run.
    static let downloadsFolder: URL = {
        let source = root.appendingPathComponent("downloads")
        let folder = temporaryFolder()
        let names = try! FileManager.default.contentsOfDirectory(atPath: source.path).filter { $0.hasSuffix(".csv") }

        for name in names {
            let text = try! Data(contentsOf: source.appendingPathComponent(name))
            try! gzipped(text).write(to: folder.appendingPathComponent(name + ".gz"))
        }
        return folder
    }()

    /// Small files in the format of Rebrickable's downloads.
    static var downloads: LDrawRebrickableDownloads {
        LDrawRebrickableDownloads(folderURL: downloadsFolder)
    }

    /// The bytes as a gzip file: a fixed header, the deflated bytes, then
    /// their CRC-32 and length.
    static func gzipped(_ data: Data) throws -> Data {
        var file = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        let crc = data.withUnsafeBytes { bytes in
            UInt32(truncatingIfNeeded: crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(bytes.count)))
        }

        file.append(try (data as NSData).compressed(using: .zlib) as Data)
        for value in [crc, UInt32(truncatingIfNeeded: data.count)] {
            withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) }
        }
        return file
    }

    /// A new, empty folder in the temporary directory.
    static func temporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LDrawRebrickableTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func data(ofDownload name: String) throws -> Data {
        try Data(contentsOf: downloadsFolder.appendingPathComponent("\(name).csv.gz"))
    }
}

/// Answers every request with what `handler` returns, and keeps the requests.
final class StubURLProtocol: URLProtocol {

    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func answer(with handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        Self.handler = handler
        seen = []
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

    override func stopLoading() {}
}
