//
//  LDrawPartOverridePresentationTests.swift
//  LDrawFeaturesTests
//
//  Tests for the text shown about the overrides folder, and for the record of
//  the outdated overrides already reported.
//
//  Created by Sergey Slobodenyuk on 2026-11-06.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

@Suite("Part overrides presentation")
struct LDrawPartOverridePresentationTests {

    /// A library and an overrides folder with `outdated` parts the library has
    /// changed since, and one part it has not.
    private struct Folders {
        let root: URL
        let library: URL
        let overrides: URL

        init(outdated: Int) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LDrawPartOverridePresentationTests-\(UUID().uuidString)")
            library = root.appendingPathComponent("ldraw")
            overrides = root.appendingPathComponent("overrides")
            for folder in [library, overrides] {
                for sub in ["parts", "p"] {
                    try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub),
                                                            withIntermediateDirectories: true)
                }
            }
            for index in 0..<outdated {
                try write("parts/\(100 + index).dat", in: library, release: "UPDATE 2022-01")
                try write("parts/\(100 + index).dat", in: overrides, release: "UPDATE 2005-01")
            }
            try write("parts/3001.dat", in: library, release: "UPDATE 2010-01")
            try write("parts/3001.dat", in: overrides, release: "UPDATE 2010-01")
        }

        func write(_ path: String, in folder: URL, release: String) throws {
            try ["0 Test Part", "0 !LDRAW_ORG Part \(release)"].joined(separator: "\r\n")
                .write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        func overridesList() -> [LDrawPartOverride] {
            let paths = LDrawPaths()
            paths.setPreferredLDrawPath(library.path)
            paths.setOverridesPath(overrides.path)
            return LDrawPartOverride.overrides(paths: paths)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("Only the overrides the library has changed since are outdated")
    func outdated() throws {
        let folders = try Folders(outdated: 2)
        defer { folders.remove() }

        #expect(LDrawPartOverridePresentation.outdated(folders.overridesList()).map(\.partName)
                == ["100.dat", "101.dat"])
    }

    @Test("The summary counts the parts and names the first five outdated ones")
    func summary() throws {
        let none = try Folders(outdated: 0)
        let many = try Folders(outdated: 7)
        defer { none.remove(); many.remove() }

        #expect(LDrawPartOverridePresentation.summary(of: []) == "None in its parts or p folders.")
        #expect(LDrawPartOverridePresentation.summary(of: none.overridesList()) == "1 part.")
        let names = "100.dat, 101.dat, 102.dat, 103.dat, 104.dat, and 2 more"
        #expect(LDrawPartOverridePresentation.summary(of: many.overridesList())
                == "8 parts. The library has a newer version of \(names).")
    }

    @Test("The list names the releases of each side and how many more there are")
    func list() throws {
        let folders = try Folders(outdated: 3)
        defer { folders.remove() }
        let outdated = LDrawPartOverridePresentation.outdated(folders.overridesList())

        #expect(LDrawPartOverridePresentation.list(ofOutdated: outdated, limit: 2)
                == "100.dat: yours 2005-01, library 2022-01\n101.dat: yours 2005-01, library 2022-01\nand 1 more")
        #expect(LDrawPartOverridePresentation.details(of: folders.overridesList())?.components(separatedBy: "\n").count
                == 3)
        #expect(LDrawPartOverridePresentation.details(of: []) == nil)
    }

    @Test("A side's note has the file's release, or says the library lacks it")
    func notes() throws {
        let folders = try Folders(outdated: 0)
        defer { folders.remove() }
        let path = folders.library.appendingPathComponent("parts/3001.dat").path

        #expect(LDrawPartOverridePresentation.note(forFileAtPath: nil) == "Not in the library")
        #expect(LDrawPartOverridePresentation.note(forFileAtPath: path)
                == "\((path as NSString).abbreviatingWithTildeInPath) — release 2010-01")
    }

    @Test("An outdated override is new to report once, and again after a later library release")
    func reporting() throws {
        let folders = try Folders(outdated: 1)
        let suite = "LDrawPartOverridePresentationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { folders.remove(); defaults.removePersistentDomain(forName: suite) }

        #expect(LDrawPartOverridePresentation.recordOutdated(folders.overridesList(), in: defaults))
        #expect(LDrawPartOverridePresentation.recordOutdated(folders.overridesList(), in: defaults) == false)

        try folders.write("parts/100.dat", in: folders.library, release: "UPDATE 2023-01")
        #expect(LDrawPartOverridePresentation.recordOutdated(folders.overridesList(), in: defaults))
        #expect(defaults.stringArray(forKey: "Part Overrides Reported") == ["100.dat 2023-01"])
    }

    @Test("A folder that lists nothing keeps the record, and a fixed override leaves it")
    func reportingKeepsUnlisted() throws {
        let folders = try Folders(outdated: 1)
        let suite = "LDrawPartOverridePresentationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { folders.remove(); defaults.removePersistentDomain(forName: suite) }

        #expect(LDrawPartOverridePresentation.recordOutdated(folders.overridesList(), in: defaults))
        #expect(LDrawPartOverridePresentation.recordOutdated([], in: defaults) == false)
        #expect(defaults.stringArray(forKey: "Part Overrides Reported") == ["100.dat 2022-01"])
        #expect(LDrawPartOverridePresentation.recordOutdated(folders.overridesList(), in: defaults) == false)

        try folders.write("parts/100.dat", in: folders.overrides, release: "UPDATE 2022-01")
        #expect(LDrawPartOverridePresentation.recordOutdated(folders.overridesList(), in: defaults) == false)
        #expect(defaults.stringArray(forKey: "Part Overrides Reported") == [])
    }
}
