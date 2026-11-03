//
//  LDrawRebrickableNetworkTests.swift
//  LDrawRebrickableTests
//
//  Tests for the downloads, against a stub protocol. No test reaches the
//  network.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawRebrickable

/// The stub protocol's answers are process-wide, so these run one at a time.
@Suite("Network, stubbed", .serialized)
struct LDrawRebrickableNetworkTests {

    private let queue = DispatchQueue(label: "LDrawRebrickableNetworkTests")

    private func downloads(in folder: URL) -> LDrawRebrickableDownloads {
        let downloads = LDrawRebrickableDownloads(folderURL: folder)
        downloads.sessionConfiguration = StubURLProtocol.configuration()
        return downloads
    }

    private func update(_ downloads: LDrawRebrickableDownloads, _ names: [String],
                        force: Bool = false) async -> ([String], Error?) {
        await withCheckedContinuation { continuation in
            _ = downloads.updateFiles(named: names, force: force, completionQueue: queue) { changed, error in
                continuation.resume(returning: (changed, error))
            }
        }
    }

    @Test("A file is fetched, kept, and not asked for again within a day")
    func downloadOnce() async throws {
        let body = try RebrickableFixtures.data(ofDownload: "themes")
        StubURLProtocol.answer { _ in
            .init(status: 200,
                  headers: ["ETag": "\"v1\"", "Last-Modified": "Sat, 24 Oct 2026 08:00:00 GMT"],
                  body: body)
        }
        let folder = RebrickableFixtures.temporaryFolder()

        let (changed, error) = await update(downloads(in: folder), ["themes"])
        #expect(error == nil)
        #expect(changed == ["themes"])
        #expect(StubURLProtocol.requests.map { $0.url?.absoluteString } ==
                ["https://cdn.rebrickable.com/media/downloads/themes.csv.gz"])

        let reread = downloads(in: folder)
        #expect(reread.hasFiles(named: ["themes"]))
        #expect(reread.checkDate(forFileNamed: "themes") != nil)
        #expect(reread.dataDate(forFileNamed: "themes") == Date(timeIntervalSince1970: 1_792_828_800))

        StubURLProtocol.answer { _ in .init(status: 500) }
        let (again, againError) = await update(reread, ["themes"])
        #expect(againError == nil)
        #expect(again.isEmpty)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("A forced check sends the ETag and keeps the file on a 304")
    func notModified() async throws {
        let body = try RebrickableFixtures.data(ofDownload: "themes")
        let folder = RebrickableFixtures.temporaryFolder()
        StubURLProtocol.answer { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: body) }
        _ = await update(downloads(in: folder), ["themes"])

        StubURLProtocol.answer { _ in .init(status: 304) }
        let (changed, error) = await update(downloads(in: folder), ["themes"], force: true)
        #expect(error == nil)
        #expect(changed.isEmpty)
        #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(try Data(contentsOf: folder.appendingPathComponent("themes.csv.gz")) == body)
    }

    @Test("A server error stops the update and says so")
    func serverError() async throws {
        StubURLProtocol.answer { _ in .init(status: 503) }
        let (changed, error) = await update(downloads(in: RebrickableFixtures.temporaryFolder()), ["themes", "sets"])
        #expect(changed.isEmpty)
        #expect((error as NSError?)?.code == LDrawRebrickableError.badResponse.rawValue)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A failed update keeps the old files, and a file that came before the error waits for the next one")
    func failedUpdateKeepsOldFiles() async throws {
        let themes = try RebrickableFixtures.data(ofDownload: "themes")
        let sets = try RebrickableFixtures.data(ofDownload: "sets")
        let folder = RebrickableFixtures.temporaryFolder()
        StubURLProtocol.answer { request in
            let isThemes = request.url!.lastPathComponent == "themes.csv.gz"
            return .init(status: 200, headers: ["ETag": "\"v1\""], body: isThemes ? themes : sets)
        }
        _ = await update(downloads(in: folder), ["themes", "sets"])

        StubURLProtocol.answer { request in
            request.url!.lastPathComponent == "themes.csv.gz"
                ? .init(status: 200, headers: ["ETag": "\"v2\""], body: sets)
                : .init(status: 503)
        }
        let (changed, error) = await update(downloads(in: folder), ["themes", "sets"], force: true)
        #expect(changed.isEmpty)
        #expect(error != nil)
        #expect(try Data(contentsOf: folder.appendingPathComponent("themes.csv.gz")) == themes)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(leftovers.allSatisfy { $0.hasPrefix(".incoming-") == false })

        StubURLProtocol.answer { request in
            request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\""
                ? .init(status: 200, headers: ["ETag": "\"v2\""], body: sets)
                : .init(status: 304)
        }
        let (retried, retryError) = await update(downloads(in: folder), ["themes", "sets"], force: true)
        #expect(retryError == nil)
        #expect(Set(retried) == ["themes", "sets"])
        #expect(try Data(contentsOf: folder.appendingPathComponent("themes.csv.gz")) == sets)
    }

    @Test("A stored file stays new until it is marked as used, across launches")
    func newFiles() async throws {
        let body = try RebrickableFixtures.data(ofDownload: "themes")
        let folder = RebrickableFixtures.temporaryFolder()
        StubURLProtocol.answer { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: body) }
        let first = downloads(in: folder)
        #expect(first.hasNewFiles(named: ["themes"]) == false)
        _ = await update(first, ["themes"])
        #expect(first.hasNewFiles(named: ["themes"]))

        StubURLProtocol.answer { _ in .init(status: 304) }
        let second = downloads(in: folder)
        _ = await update(second, ["themes"], force: true)
        #expect(second.hasNewFiles(named: ["themes"]))

        second.markFilesAsUsed(named: ["themes"])
        #expect(downloads(in: folder).hasNewFiles(named: ["themes"]) == false)
    }
}
