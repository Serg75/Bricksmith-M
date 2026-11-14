//
//  LDrawLibraryReleaseTests.swift
//  LDrawLibraryUpdateTests
//
//  Tests for reading LDraw's list of releases, choosing what to install, and
//  telling which update a folder holds.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//

import Testing
import Foundation
import LDrawLibraryUpdate

@Suite("Release list")
struct LDrawLibraryReleaseTests {

    /// Rows in the server's format. The sizes are made up.
    private let text = """
        UPDATE\t1997-15\t1997-10-29\tARJ\thttps://library.ldraw.org/library/updates/lcad9715.exe\t79577\taa
        UPDATE\t2026-08\t2026-08-31\tARJ\thttps://library.ldraw.org/library/updates/lcad2608.exe\t800\tbb
        UPDATE\t2026-08\t2026-08-31\tZIP\thttps://library.ldraw.org/library/updates/lcad2608.zip\t800\tCC
        UPDATE\t2026-10\t2026-10-26\tZIP\thttps://library.ldraw.org/library/updates/lcad2610.zip\t1000\tee
        UPDATE\t2026-09\t2026-09-30\tZIP\thttps://library.ldraw.org/library/updates/lcad2609.zip\t900\tdd
        COMPLETE\t2026-10\t2026-10-26\tZIP\thttps://library.ldraw.org/library/updates/complete.zip\t5000\tff
        BASE\t0.27\t2026-11-09\tZIP\thttps://library.ldraw.org/library/updates/ldraw027.zip\t1175404\t00
        """

    private func identifiers(_ releases: [LDrawLibraryRelease]) -> [String] {
        releases.map { $0.isComplete ? "complete" : $0.identifier }
    }

    @Test("A row whose update is not a year and number is left out")
    func malformedIdentifier() throws {
        let rows = text + """

            UPDATE\tdraft\t2026-11-01\tZIP\thttps://library.ldraw.org/library/updates/draft.zip\t10\t11
            UPDATE\t2026-1\t2026-11-01\tARJ\thttps://library.ldraw.org/library/updates/lcad261.exe\t10\t11
            UPDATE\t２０２６-１１\t2026-11-01\tZIP\thttps://library.ldraw.org/library/updates/wide.zip\t10\t11
            COMPLETE\tlatest\t2026-11-01\tZIP\thttps://library.ldraw.org/library/updates/complete2.zip\t10\t11
            """
        let list = try #require(LDrawLibraryReleaseList(text: rows))

        #expect(list.latestIdentifier == "2026-10")
        #expect(list.updates.map(\.identifier) == ["2026-08", "2026-09", "2026-10"])
        #expect(list.complete.identifier == "2026-10")
        #expect(identifiers(list.releasesToInstall(after: "2026-10")).isEmpty)
        #expect(identifiers(list.releasesToInstall(after: "2026-09")) == ["2026-10"])
    }

    @Test("The zip updates are read oldest first, with the complete library")
    func parse() throws {
        let list = try #require(LDrawLibraryReleaseList(text: text))

        #expect(list.updates.map(\.identifier) == ["2026-08", "2026-09", "2026-10"])
        #expect(list.latestIdentifier == "2026-10")
        #expect(list.complete.isComplete)
        #expect(list.complete.byteCount == 5000)

        let first = try #require(list.updates.first)
        #expect(first.url.absoluteString == "https://library.ldraw.org/library/updates/lcad2608.zip")
        #expect(first.byteCount == 800)
        #expect(first.md5 == "cc")
        #expect(first.isComplete == false)
    }

    @Test("A list without the complete library is not read")
    func noComplete() {
        let rows = text.split(separator: "\n").filter { !$0.hasPrefix("COMPLETE") }.joined(separator: "\n")
        #expect(LDrawLibraryReleaseList(text: rows) == nil)
        #expect(LDrawLibraryReleaseList(text: "<html>Not found</html>") == nil)
    }

    @Test("An archive that is not at an https address is left out")
    func plainHTTP() throws {
        let rows = text.replacingOccurrences(of: "https://library.ldraw.org/library/updates/lcad2610.zip",
                                             with: "http://library.ldraw.org/library/updates/lcad2610.zip")
        let list = try #require(LDrawLibraryReleaseList(text: rows))

        #expect(list.updates.map(\.identifier) == ["2026-08", "2026-09"])
        // The newest update has no usable archive, so only the complete library will do.
        #expect(identifiers(list.releasesToInstall(after: "2026-09")) == ["complete"])
    }

    @Test("A folder gets the updates after its own, or nothing when it has the newest")
    func updatesAfter() throws {
        let list = try #require(LDrawLibraryReleaseList(text: text))

        #expect(identifiers(list.releasesToInstall(after: "2026-10")).isEmpty)
        #expect(identifiers(list.releasesToInstall(after: "2026-11")).isEmpty)
        #expect(identifiers(list.releasesToInstall(after: "2026-09")) == ["2026-10"])
        #expect(identifiers(list.releasesToInstall(after: "2026-08")) == ["2026-09", "2026-10"])
    }

    @Test("The complete library is used for an unknown update, a gap, or a bigger sum of updates")
    func complete() throws {
        let list = try #require(LDrawLibraryReleaseList(text: text))

        #expect(identifiers(list.releasesToInstall(after: nil)) == ["complete"])
        // 1997-15 has no zip archive, and is newer than 1997-14.
        #expect(identifiers(list.releasesToInstall(after: "1997-14")) == ["complete"])

        let small = text.replacingOccurrences(of: "complete.zip\t5000", with: "complete.zip\t1900")
        let smallList = try #require(LDrawLibraryReleaseList(text: small))
        #expect(identifiers(smallList.releasesToInstall(after: "2026-08")) == ["complete"])
        #expect(identifiers(smallList.releasesToInstall(after: "2026-09")) == ["2026-10"])
    }

    @Test("A complete library older than the newest update is followed by the updates after it")
    func olderComplete() throws {
        let older = text.replacingOccurrences(of: "COMPLETE\t2026-10", with: "COMPLETE\t2026-09")
        let list = try #require(LDrawLibraryReleaseList(text: older))

        #expect(list.latestIdentifier == "2026-10")
        #expect(identifiers(list.releasesToInstall(after: "2026-10")).isEmpty)
        #expect(identifiers(list.releasesToInstall(after: "2026-09")) == ["2026-10"])
        #expect(identifiers(list.releasesToInstall(after: nil)) == ["complete", "2026-10"])
        #expect(identifiers(list.releasesToInstall(after: "1997-14")) == ["complete", "2026-10"])

        // With no zip archive after it, the complete library is still the closest.
        let gap = older.replacingOccurrences(of: "lcad2610.zip", with: "lcad2610.exe")
            .replacingOccurrences(of: "2026-10-26\tZIP\thttps://library.ldraw.org/library/updates/lcad2610",
                                  with: "2026-10-26\tARJ\thttps://library.ldraw.org/library/updates/lcad2610")
        let gapList = try #require(LDrawLibraryReleaseList(text: gap))
        #expect(gapList.latestIdentifier == "2026-10")
        #expect(identifiers(gapList.releasesToInstall(after: nil)) == ["complete"])
        #expect(identifiers(gapList.releasesToInstall(after: "2026-08")) == ["complete"])
        #expect(identifiers(gapList.releasesToInstall(after: "2026-09")).isEmpty)
    }

    @Test("A complete library newer than every update is used alone")
    func newerComplete() throws {
        let newer = text.replacingOccurrences(of: "COMPLETE\t2026-10", with: "COMPLETE\t2026-11")
        let list = try #require(LDrawLibraryReleaseList(text: newer))

        #expect(list.latestIdentifier == "2026-11")
        #expect(identifiers(list.releasesToInstall(after: "2026-10")) == ["complete"])
        #expect(identifiers(list.releasesToInstall(after: "2026-11")).isEmpty)
    }

    @Test("A folder's update is the newest of the release notes in its models folder")
    func installedRelease() throws {
        let folder = try LibraryUpdateFixtures.folder(with: [
            "models/Note9715CA.txt": "",
            "models/Note0801CA.txt": "",
            "models/Note0801CA_a.txt": "",
            "models/Note0801NonCA.txt": "",
            "models/Note2610CA.txt": "",
            "models/note2609ca.TXT": "",
            "models/Note26xxCA.txt": "",
            "models/Note9900CA.txt": "",
            "models/car.dat": "",
        ])
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: folder) == "2026-10")

        let old = try LibraryUpdateFixtures.folder(with: ["MODELS/NOTE9715CA.TXT": ""])
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: old) == "1997-15")

        let none = try LibraryUpdateFixtures.folder(with: ["parts/3001.dat": "", "models/car.dat": ""])
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: none) == nil)
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: none.appendingPathComponent("missing")) == nil)
    }
}
