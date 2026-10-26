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
            withPartLinks: nil, colorLinks: [4: 4], relations: nil, knownPartNumbers: nil))
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
        #expect(session.effectiveLimit.kind == .none)

        let count = try posts(of: session) { try store.saveSetInventory(set("42115-1", "3001")) }
        #expect(count >= 1)
        #expect(session.effectiveLimit.kind == .inventory)
    }

    @Test("The part library's keywords reach the identity map")
    func catalogRecords() throws {
        let session = LDrawPartLimitSession(store: LDrawInventoryStore(folderURL: folder))
        session.setCatalogRecords([[PART_NUMBER_KEY: "2431px7.dat", PART_KEYWORDS_KEY: ["Rebrickable 2431pr0014"]]])
        #expect(session.identity.rebrickablePartNumber(forPartName: "2431px7.dat") == "2431pr0014")
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
