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

    @Test("Files stored after the last build are built on the next update, even when nothing changed since")
    func buildRetried() async throws {
        serveFixtures()
        let updater = updater()
        let _: (Bool, Error?) = await withCheckedContinuation { continuation in
            _ = updater.updateCatalog(forcing: false) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(updater.downloads.hasNewFiles(named: LDrawRebrickableDownloads.catalogFileNames()) == false)

        // A file stored by a run whose build did not finish.
        let _: ([String], Error?) = await withCheckedContinuation { continuation in
            _ = updater.downloads.updateFiles(named: ["themes"], force: true, completionQueue: nil) {
                continuation.resume(returning: ($0, $1))
            }
        }
        #expect(updater.downloads.hasNewFiles(named: ["themes"]))

        StubURLProtocol.answer { _ in .init(status: 304) }
        let (changed, error): (Bool, Error?) = await withCheckedContinuation { continuation in
            _ = updater.updateCatalog(forcing: true) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(error == nil)
        #expect(changed)
        #expect(updater.downloads.hasNewFiles(named: ["themes"]) == false)
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

    @Test("Saved data takes the folder's color links and keeps its part links")
    func updateColorLinks() throws {
        let updater = updater()
        try updater.updateIdentityData()
        #expect(updater.store.rebrickableIdentityData() == nil)

        try updater.store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: ["3001": "3001"], colorLinks: [179: [315]], relations: nil, knownPartNumbers: nil,
            rubberPartNumbers: nil))
        try updater.updateIdentityData()

        let data = updater.store.rebrickableIdentityData()
        #expect(LDrawPartIdentity.colorLinks(inRebrickableData: data) == LDrawRebrickableColors.builtInColorLinks())
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        #expect(identity.rebrickablePartNumber(forPartName: "3001") == "3001")
        #expect(identity.rebrickableColorID(forColorCode: LDrawColorT(rawValue: 179)!) == 179)
        #expect(LDrawPartIdentity.rubberPartNumbers(inRebrickableData: data) == nil)
    }

    @Test("Saved data with no rubber parts reads them from the downloaded part list")
    func updateRubberParts() throws {
        let updater = updater()
        let parts = updater.downloads.localURL(forFileNamed: "parts")
        try FileManager.default.createDirectory(at: updater.downloads.folderURL, withIntermediateDirectories: true)
        try RebrickableFixtures.data(ofDownload: "parts").write(to: parts)
        try updater.store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: nil, colorLinks: LDrawRebrickableColors.builtInColorLinks(), relations: nil,
            knownPartNumbers: nil, rubberPartNumbers: nil))

        try updater.updateIdentityData()
        let data = updater.store.rebrickableIdentityData()
        #expect(LDrawPartIdentity.rubberPartNumbers(inRebrickableData: data) == ["3483"])
    }
}
