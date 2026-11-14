//
//  LDrawLibraryUpdatePolicyTests.swift
//  LDrawLibraryUpdateTests
//
//  Tests for when a host looks for an update and what it does with one, and
//  for the record of an update's new parts.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//

import Testing
import Foundation
import LDrawLibraryUpdate

@Suite("Update policy")
struct LDrawLibraryUpdatePolicyTests {

    private let list = LDrawLibraryReleaseList(text: """
        UPDATE\t2026-10\t2026-10-26\tZIP\thttps://library.ldraw.org/library/updates/lcad2610.zip\t1000\taa
        UPDATE\t2026-11\t2026-11-30\tZIP\thttps://library.ldraw.org/library/updates/lcad2611.zip\t1000\tbb
        COMPLETE\t2026-11\t2026-11-30\tZIP\thttps://library.ldraw.org/library/updates/complete.zip\t5000\tcc
        """)!

    @Test("A launch looks at most once a day, and never in Never mode")
    func launchCheck() {
        let now = Date()
        func isDue(_ mode: LDrawLibraryUpdateMode, _ checked: Date?) -> Bool {
            LDrawLibraryUpdatePolicy.isLaunchCheckDue(mode: mode, lastCheckDate: checked, now: now)
        }

        #expect(isDue(.ask, nil))
        #expect(isDue(.install, now.addingTimeInterval(-25 * 60 * 60)))
        #expect(isDue(.ask, now.addingTimeInterval(-23 * 60 * 60)) == false)
        #expect(isDue(.ask, now.addingTimeInterval(60)), "A date in the future is no reason to wait")
        #expect(isDue(.never, nil) == false)
        #expect(isDue(LDrawLibraryUpdateMode(rawValue: 7)!, nil), "A value saved by hand asks")
    }

    @Test("A check the user asked for says when there is nothing, and offers anything")
    func askedByUser() {
        func action(_ installed: String?, _ mode: LDrawLibraryUpdateMode) -> LDrawLibraryUpdateAction {
            LDrawLibraryUpdatePolicy.action(for: list, installed: installed, mode: mode, skippedRelease: "2026-11",
                                            askedByUser: true)
        }

        #expect(action("2026-11", .install) == .upToDate)
        #expect(action("2026-12", .install) == .upToDate)
        #expect(action("2026-09", .install) == .offer)
        #expect(action(nil, .never) == .offer)
    }

    @Test("A check the user asked for says when no zip archive reaches the newest update")
    func noArchive() throws {
        // 2026-12 comes only as an ARJ archive, and the complete library is older.
        let gap = try #require(LDrawLibraryReleaseList(text: """
            UPDATE\t2026-11\t2026-11-30\tZIP\thttps://library.ldraw.org/library/updates/lcad2611.zip\t1000\tbb
            UPDATE\t2026-12\t2026-12-30\tARJ\thttps://library.ldraw.org/library/updates/lcad2612.exe\t1000\tdd
            COMPLETE\t2026-11\t2026-11-30\tZIP\thttps://library.ldraw.org/library/updates/complete.zip\t5000\tcc
            """))
        func action(_ asked: Bool) -> LDrawLibraryUpdateAction {
            LDrawLibraryUpdatePolicy.action(for: gap, installed: "2026-11", mode: .ask, skippedRelease: nil,
                                            askedByUser: asked)
        }

        #expect(action(true) == .noArchive)
        #expect(action(false) == .none)
    }

    @Test("A launch skips the skipped update, installs updates in Install mode, and offers the complete library")
    func atLaunch() {
        func action(_ installed: String?, _ mode: LDrawLibraryUpdateMode,
                    skipped: String? = nil) -> LDrawLibraryUpdateAction {
            LDrawLibraryUpdatePolicy.action(for: list, installed: installed, mode: mode, skippedRelease: skipped,
                                            askedByUser: false)
        }

        #expect(action("2026-11", .ask) == .none)
        #expect(action("2026-09", .ask) == .offer)
        #expect(action("2026-09", .install) == .install)
        #expect(action("2026-09", .install, skipped: "2026-11") == .none)
        #expect(action("2026-09", .ask, skipped: "2026-10") == .offer)
        #expect(action(nil, .install) == .offer)
    }

    @Test("The new parts are kept as a dictionary and read back for their folder only")
    func newParts() throws {
        let parts = LDrawLibraryNewParts(partNames: ["3001.dat", "99999.dat"], releaseIdentifier: "2026-11",
                                         folderPath: "/Users/me/ldraw")
        let read = try #require(LDrawLibraryNewParts(dictionary: parts.dictionaryRepresentation()))

        #expect(read.partNames == ["3001.dat", "99999.dat"])
        #expect(read.releaseIdentifier == "2026-11")
        #expect(read.isOf(folderPath: "/Users/me/ldraw"))
        #expect(read.isOf(folderPath: "/Users/me/ldraw/"))
        #expect(read.isOf(folderPath: "/Users/me/other/../ldraw"))
        #expect(read.isOf(folderPath: "/Users/me/ldraw2") == false)
        #expect(read.isOf(folderPath: nil) == false)
    }

    @Test("A dictionary that is not a record of new parts is not read")
    func badNewParts() {
        let good: [String: Any] = ["folder": "/ldraw", "release": "2026-11", "names": ["3001.dat"]]

        #expect(LDrawLibraryNewParts(dictionary: good) != nil)
        #expect(LDrawLibraryNewParts(dictionary: nil) == nil)
        #expect(LDrawLibraryNewParts(dictionary: good.merging(["folder": 3]) { $1 }) == nil)
        #expect(LDrawLibraryNewParts(dictionary: good.merging(["release": NSNull()]) { $1 }) == nil)
        #expect(LDrawLibraryNewParts(dictionary: good.merging(["names": "3001.dat"]) { $1 }) == nil)
        #expect(LDrawLibraryNewParts(dictionary: good.merging(["names": ["3001.dat", 7]]) { $1 }) == nil)
    }
}
