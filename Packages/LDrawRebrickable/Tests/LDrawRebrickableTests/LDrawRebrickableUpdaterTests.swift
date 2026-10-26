//
//  LDrawRebrickableUpdaterTests.swift
//  LDrawRebrickableTests
//
//  Tests for keeping a store's Rebrickable data up to date, against the
//  fixture files served by the stub protocol.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory
import LDrawRebrickable

extension LDrawRebrickableNetworkTests {

    /// Serves every download from the fixtures.
    private func serveFixtures() {
        StubURLProtocol.answer { request in
            let name = request.url!.lastPathComponent.replacingOccurrences(of: ".csv.gz", with: "")
            guard let body = try? RebrickableFixtures.data(ofDownload: name) else { return .init(status: 404) }
            return .init(status: 200, headers: ["ETag": "\"\(name)\""], body: body)
        }
    }

    private func updater() -> LDrawRebrickableUpdater {
        let folder = RebrickableFixtures.temporaryFolder()
        let downloads = LDrawRebrickableDownloads(folderURL: folder.appendingPathComponent("downloads"))
        downloads.sessionConfiguration = StubURLProtocol.configuration()
        return LDrawRebrickableUpdater(downloads: downloads,
                                       store: LDrawInventoryStore(folderURL: folder.appendingPathComponent("store")))
    }

    @Test("An update downloads the files, then builds and saves the catalog; a second one changes nothing")
    func updateCatalog() async throws {
        serveFixtures()
        let updater = updater()
        #expect(updater.hasCatalog == false)

        let (changed, error): (Bool, Error?) = await withCheckedContinuation { continuation in
            _ = updater.updateCatalog(forcing: false) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(error == nil)
        #expect(changed)
        #expect(updater.hasCatalog)
        #expect(updater.isUpdating == false)
        #expect(updater.store.availability()?.partCount ?? 0 > 0)

        let (again, _): (Bool, Error?) = await withCheckedContinuation { continuation in
            _ = updater.updateCatalog(forcing: false) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(again == false)
    }

    @Test("A set is imported from the downloads and saved in the store")
    func importFromDownloads() async throws {
        serveFixtures()
        let updater = updater()
        _ = await withCheckedContinuation { continuation in
            _ = updater.updateCatalog(forcing: false) { _, _ in continuation.resume() }
        }

        let (set, error): (LDrawSetInventory?, Error?) = await withCheckedContinuation { continuation in
            updater.importSet(number: "42115", client: nil) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(error == nil)
        #expect(set?.setNumber == "42115-1")
        #expect(updater.store.setNumbers() == ["42115-1"])
    }

    @Test("An unknown set is an error, and nothing is saved")
    func importUnknown() async throws {
        serveFixtures()
        let updater = updater()
        _ = await withCheckedContinuation { continuation in
            _ = updater.updateCatalog(forcing: false) { _, _ in continuation.resume() }
        }

        let (set, error): (LDrawSetInventory?, Error?) = await withCheckedContinuation { continuation in
            updater.importSet(number: "99999", client: nil) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(set == nil)
        #expect((error as NSError?)?.code == LDrawRebrickableError.notFound.rawValue)
        #expect(updater.store.setNumbers().isEmpty)
    }
}
