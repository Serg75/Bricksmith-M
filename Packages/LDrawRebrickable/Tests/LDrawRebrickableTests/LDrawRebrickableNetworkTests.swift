//
//  LDrawRebrickableNetworkTests.swift
//  LDrawRebrickableTests
//
//  Tests for the downloads and the API client, against a stub protocol. No
//  test reaches the network.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory
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

    private func client() -> LDrawRebrickableClient {
        let client = LDrawRebrickableClient(apiKey: "TESTKEY")
        client.sessionConfiguration = StubURLProtocol.configuration()
        client.minimumInterval = 0
        client.completionQueue = queue
        return client
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Downloads

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

    // MARK: - API client

    @Test("A list is read across its pages, with the key in the header")
    func paging() async throws {
        StubURLProtocol.answer { request in
            let page = request.url?.query?.contains("page=2") == true
            let next: Any = page ? NSNull() : "https://rebrickable.com/api/v3/lego/colors/?page=2&page_size=1000"
            return .init(status: 200, body: self.json(["next": next, "results": [["id": page ? 2 : 1]]]))
        }
        let results: [[AnyHashable: Any]]? = await withCheckedContinuation { continuation in
            client().fetchAllResults(atPath: "lego/colors/", parameters: nil) { results, _ in
                continuation.resume(returning: results)
            }
        }
        #expect(results?.compactMap { $0["id"] as? Int } == [1, 2])
        #expect(StubURLProtocol.requests.count == 2)
        #expect(StubURLProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "key TESTKEY" })
        #expect(StubURLProtocol.requests.first?.url?.query == "page_size=1000")
    }

    @Test("A next page on another server is refused, and the key does not go there")
    func foreignNextPage() async throws {
        StubURLProtocol.answer { _ in
            .init(status: 200, body: self.json(["next": "https://example.com/steal", "results": []]))
        }
        let error: Error? = await withCheckedContinuation { continuation in
            client().fetchAllResults(atPath: "lego/colors/", parameters: nil) { _, error in
                continuation.resume(returning: error)
            }
        }
        #expect((error as NSError?)?.code == LDrawRebrickableError.badResponse.rawValue)
        #expect(StubURLProtocol.requests.allSatisfy { $0.url?.host == "rebrickable.com" })
    }

    @Test("A 429 is retried after the wait the server names")
    func tooManyRequests() async throws {
        var times: [Date] = []
        StubURLProtocol.answer { _ in
            times.append(Date())
            return times.count == 1 ? .init(status: 429, headers: ["Retry-After": "1"])
                                    : .init(status: 200, body: self.json(["set_num": "42115-1"]))
        }
        let object: [AnyHashable: Any]? = await withCheckedContinuation { continuation in
            client().fetchObject(atPath: "lego/sets/42115-1/") { object, _ in
                continuation.resume(returning: object)
            }
        }
        #expect(object?["set_num"] as? String == "42115-1")
        #expect(StubURLProtocol.requests.count == 2)
        #expect(times.count == 2 && times[1].timeIntervalSince(times[0]) >= 0.9)
    }

    @Test("A 429 that asks for too long a wait gives up at once")
    func tooLongAWait() async throws {
        StubURLProtocol.answer { _ in .init(status: 429, headers: ["Retry-After": "3600"]) }
        let error: Error? = await withCheckedContinuation { continuation in
            client().fetchObject(atPath: "lego/sets/42115-1/") { _, error in
                continuation.resume(returning: error)
            }
        }
        #expect((error as NSError?)?.code == LDrawRebrickableError.tooManyRequests.rawValue)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A refused key and an unknown item come back as their own errors", arguments: [
        (401, LDrawRebrickableError.badKey),
        (403, LDrawRebrickableError.badKey),
        (404, LDrawRebrickableError.notFound),
        (500, LDrawRebrickableError.badResponse),
    ])
    func errors(status: Int, expected: LDrawRebrickableError.Code) async throws {
        StubURLProtocol.answer { _ in .init(status: status) }
        let error: Error? = await withCheckedContinuation { continuation in
            client().fetchObject(atPath: "lego/sets/1-1/") { _, error in
                continuation.resume(returning: error)
            }
        }
        #expect((error as NSError?)?.code == expected.rawValue)
    }

    // MARK: - API set import and colors

    @Test("A set fetched through the API keeps Rebrickable's LDraw ids and links them")
    func fetchSet() async throws {
        let setObject: [String: Any] = ["set_num": "60000-1", "name": "Fire Motorcycle", "year": 2013,
                                        "set_img_url": "https://cdn.rebrickable.com/60000-1.jpg"]
        let rows: [[String: Any]] = [
            ["part": ["part_num": "3001", "external_ids": ["LDraw": ["3001"]]],
             "color": ["id": 4, "external_ids": ["LDraw": ["ext_ids": [4], "ext_descrs": [["Red"]]]]],
             "quantity": 2, "is_spare": false],
            ["part": ["part_num": "3001", "external_ids": ["LDraw": ["3001"]]],
             "color": ["id": 4, "external_ids": ["LDraw": ["ext_ids": [4]]]],
             "quantity": 1, "is_spare": true],
            ["part": ["part_num": "3626cpr0001", "external_ids": ["LDraw": ["3626cp01", "3626bp01"]]],
             "color": ["id": 14], "quantity": 1, "is_spare": false],
        ]
        StubURLProtocol.answer { request in
            if request.url?.absoluteString.contains("/parts/") == true {
                return .init(status: 200, body: self.json(["next": NSNull(), "results": rows]))
            }
            return .init(status: 200, body: self.json(setObject))
        }

        let (set, links): (LDrawSetInventory?, [String: String]) = await withCheckedContinuation { continuation in
            LDrawRebrickableSetImporter.fetchSetInventory(number: "60000", client: client(),
                                                         setList: nil) { set, links, _ in
                continuation.resume(returning: (set, links))
            }
        }
        let fetched = try #require(set)
        #expect(fetched.setNumber == "60000-1")
        #expect(fetched.source == "rebrickable-api")
        #expect(fetched.items.count == 2)
        let brick = try #require(fetched.items.first { $0.rebrickablePartNumber == "3001" })
        #expect(brick.quantity == 2)
        #expect(brick.spareQuantity == 1)
        #expect(brick.ldrawPartName == "3001.dat")
        #expect(brick.ldrawColorCode.rawValue == 4)
        #expect(links == ["3001.dat": "3001", "3626cp01.dat": "3626cpr0001", "3626bp01.dat": "3626cpr0001"])

        let partsRequest = try #require(StubURLProtocol.requests.last?.url?.query)
        #expect(partsRequest.contains("inc_minifig_parts=1"))
        #expect(partsRequest.contains("inc_part_details=1"))
    }

    @Test("Color links are fetched from the API, and kept in the folder over the shipped table")
    func fetchColors() async throws {
        StubURLProtocol.answer { _ in
            .init(status: 200, body: self.json(["next": NSNull(), "results": [
                ["id": 0, "external_ids": ["LDraw": ["ext_ids": [0, 256]]]],
                ["id": 326, "external_ids": ["LDraw": ["ext_ids": [330]]]],
                ["id": 9999, "external_ids": [:]],
            ]]))
        }
        let links: [NSNumber: [NSNumber]]? = await withCheckedContinuation { continuation in
            LDrawRebrickableColors.fetchColorLinks(with: client()) { links, _ in
                continuation.resume(returning: links)
            }
        }
        #expect(links == [0: [0, 256], 326: [330]])

        let folder = RebrickableFixtures.temporaryFolder()
        #expect(LDrawRebrickableColors.colorLinks(forFolder: folder) == LDrawRebrickableColors.builtInColorLinks())
        try LDrawRebrickableColors.saveFetchedColorLinks(links!, inFolder: folder)
        #expect(LDrawRebrickableColors.colorLinks(forFolder: folder) == [0: [0, 256], 326: [330]])
    }
}
