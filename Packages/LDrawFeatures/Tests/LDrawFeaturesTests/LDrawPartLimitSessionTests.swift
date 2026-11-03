//
//  LDrawPartLimitSessionTests.swift
//  LDrawFeaturesTests
//
//  Tests for the session that holds the editor's parts limit.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures
import LDrawInventory

@Suite("Parts limit session")
final class LDrawPartLimitSessionTests {

    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("LDrawPartLimitSessionTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func set(_ number: String, _ part: String) -> LDrawSetInventory {
        let item = LDrawInventoryItem(rebrickablePartNumber: part, rebrickableColorID: 4, ldrawPartName: nil,
                                      ldrawColorCode: LDrawColorT(rawValue: -1)!, quantity: 2, spareQuantity: 0)
        return LDrawSetInventory(setNumber: number, name: number, year: 2025, themeName: nil, imageURL: nil,
                                 items: [item], fetchDate: nil, source: nil)
    }

    /// Counts the session's notifications while `body` runs.
    private func posts(of session: LDrawPartLimitSession, during body: () throws -> Void) rethrows -> Int {
        var count = 0
        let observer = NotificationCenter.default.addObserver(forName: .LDrawPartLimitDidChange,
                                                              object: session, queue: nil) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        try body()
        return count
    }

    @Test("A session starts with no limit, and a new limit builds a new table and posts once")
    func settingTheLimit() throws {
        let store = LDrawInventoryStore(folderURL: folder)
        try store.saveSetInventory(set("42115-1", "3001"))
        try store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: nil, colorLinks: [4: 4], relations: nil, knownPartNumbers: nil, rubberPartNumbers: nil))
        let session = LDrawPartLimitSession(store: store)

        #expect(session.limit.kind == .none)
        #expect(session.table.limit.isRestricting == false)

        let count = posts(of: session) {
            session.limit = LDrawPartLimit.inventory("42115-1")
            session.limit = LDrawPartLimit.inventory("42115-1")
        }
        #expect(count == 1)
        #expect(session.table.ownedCount(forPartNamed: "3001.dat", colorCode: LDrawColorT(rawValue: 4)!) == 2)
    }

    @Test("A limit on an inventory the store lacks is in force as no limit, until the set is imported")
    func missingInventory() throws {
        let store = LDrawInventoryStore(folderURL: folder)
        let session = LDrawPartLimitSession(store: store)
        session.limit = LDrawPartLimit.inventory("42115-1")

        #expect(session.limit.kind == .inventory)
        #expect(session.table.limit.kind == .none)

        let count = try posts(of: session) { try store.saveSetInventory(set("42115-1", "3001")) }
        #expect(count >= 1)
        #expect(session.table.limit.kind == .inventory)
    }

    @Test("The part library's keywords reach the identity map")
    func catalogRecords() throws {
        let session = LDrawPartLimitSession(store: LDrawInventoryStore(folderURL: folder))
        session.setCatalogRecords([[PART_NUMBER_KEY: "2431px7.dat", PART_KEYWORDS_KEY: ["Rebrickable 2431pr0014"]]],
                                  rubberColorCodes: nil)
        #expect(session.identity.rebrickablePartNumber(forPartName: "2431px7.dat") == "2431pr0014")
    }

    @Test("The identity map built off the main thread is kept, and later callers get it at once")
    @MainActor
    func preparingTheIdentity() async throws {
        let store = LDrawInventoryStore(folderURL: folder)
        try store.saveRebrickableIdentityData(LDrawPartIdentity.rebrickableData(
            withPartLinks: nil, colorLinks: nil, relations: [["M", "12825", "2555"]], knownPartNumbers: nil,
            rubberPartNumbers: nil))
        let session = LDrawPartLimitSession(store: store)

        #expect(session.preparedIdentity == nil)
        await withCheckedContinuation { done in
            session.prepareIdentity { done.resume() }
        }
        let prepared = try #require(session.preparedIdentity)
        #expect(prepared.moldVariants(ofPartNumber: "2555") == ["12825"])
        #expect(session.identity === prepared)

        var calledAtOnce = false
        session.prepareIdentity { calledAtOnce = true }
        #expect(calledAtOnce)
    }

    @Test("The year Available now counts back from can be set")
    func year() {
        let session = LDrawPartLimitSession(store: LDrawInventoryStore(folderURL: folder))
        let now = Calendar.current.component(.year, from: Date())
        #expect(session.currentYear == now)
        session.currentYear = 2020
        #expect(session.currentYear == 2020)
    }
}
