//
//  LDrawPartOverrideTests.swift
//  UnitTests
//
//  Tests for the overrides folder: which file a part name finds, and which
//  overrides the library has newer versions of.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//

import Testing
import Foundation
import LDrawCore

@Suite("The overrides folder")
struct LDrawPartOverrideTests {

    /// A library and an overrides folder in a new temporary folder.
    private struct Folders {
        let root: URL
        let library: URL
        let overrides: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LDrawPartOverrideTests-\(UUID().uuidString)")
            library = root.appendingPathComponent("ldraw")
            overrides = root.appendingPathComponent("overrides")
            for folder in [library, overrides] {
                for sub in ["parts/s", "p/48"] {
                    try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub),
                                                            withIntermediateDirectories: true)
                }
            }
        }

        func write(_ path: String, in folder: URL, typeLine: String?) throws {
            var lines = ["0 Test Part", "0 Name: \((path as NSString).lastPathComponent)", "0 Author: Test"]
            if let typeLine { lines.append(typeLine) }
            lines.append("1 16 0 0 0 1 0 0 0 1 0 0 0 1 stud.dat")
            try lines.joined(separator: "\r\n")
                .write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        func paths(withOverrides: Bool = true) -> LDrawPaths {
            let paths = LDrawPaths()
            paths.setPreferredLDrawPath(library.path)
            if withOverrides { paths.setOverridesPath(overrides.path) }
            return paths
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("The release is read from the !LDRAW_ORG line",
          arguments: [("0 !LDRAW_ORG Part UPDATE 2022-01", "2022-01"),
                      ("0 !LDRAW_ORG Subpart UPDATE 2012-02", "2012-02"),
                      ("0 !LDRAW_ORG Part Alias UPDATE 2004-03", "2004-03"),
                      ("0 LDRAW_ORG Part UPDATE 2003-01", "2003-01"),
                      ("0 !ldraw_org part update 2019-01", "2019-01"),
                      ("0 !LDRAW_ORG Part ORIGINAL", "ORIGINAL")])
    func releaseSpellings(line: String, expected: String) {
        let text = ["0 Brick  2 x  4", "0 Name: 3001.dat", line, "0 BFC CERTIFY CCW"].joined(separator: "\n")
        #expect(LDrawPartOverride.update(inText: text) == expected)
    }

    @Test("An unofficial part, or a type line after the header, has no release")
    func noRelease() {
        #expect(LDrawPartOverride.update(inText: "0 Part\n0 !LDRAW_ORG Unofficial_Part\n") == nil)
        #expect(LDrawPartOverride.update(inText: "0 Part\n1 16 0 0 0 1 0 0 0 1 0 0 0 1 a.dat\n"
                                                 + "0 !LDRAW_ORG Part UPDATE 2022-01\n") == nil)
    }

    @Test("A header that starts with a byte order mark or a FILE line is read")
    func headerStarts() {
        #expect(LDrawPartOverride.update(inText: "\u{FEFF}0 Part\n0 !LDRAW_ORG Part UPDATE 2020-01") == "2020-01")
        #expect(LDrawPartOverride.update(inText: "0 FILE s\\a.dat\n0 Part\n0 !LDRAW_ORG Subpart UPDATE 2012-02")
                == "2012-02")
    }

    @Test("A part in the overrides folder wins over the library's")
    func overrideWins() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try folders.write("parts/3001.dat", in: folders.library, typeLine: nil)
        try folders.write("parts/3001.dat", in: folders.overrides, typeLine: nil)
        try folders.write("parts/s/3001s01.dat", in: folders.library, typeLine: nil)
        try folders.write("p/48/1-4cyli.dat", in: folders.overrides, typeLine: nil)

        let paths = folders.paths()
        let override = folders.overrides.appendingPathComponent("parts/3001.dat").path
        let library = folders.library.appendingPathComponent("parts/3001.dat").path

        #expect(paths.path(forPartName: "3001.dat") == override)
        #expect(paths.libraryPath(forPartName: "3001.dat") == library)
        #expect(paths.path(forPartName: "s\\3001s01.dat")
                == folders.library.appendingPathComponent("parts/s/3001s01.dat").path)
        #expect(paths.path(forPartName: "48\\1-4cyli.dat")
                == folders.overrides.appendingPathComponent("p/48/1-4cyli.dat").path)
        #expect(folders.paths(withOverrides: false).path(forPartName: "3001.dat") == library)
    }

    @Test("Clearing the folder goes back to the library's part")
    func clearing() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try folders.write("parts/3001.dat", in: folders.library, typeLine: nil)
        try folders.write("parts/3001.dat", in: folders.overrides, typeLine: nil)

        let paths = folders.paths()
        _ = paths.path(forPartName: "3001.dat")
        paths.setOverridesPath("")

        #expect(paths.overridesPath() == nil)
        #expect(paths.path(forPartName: "3001.dat") == folders.library.appendingPathComponent("parts/3001.dat").path)
    }

    @Test("Each override is listed with its name, and outdated when the library's release is later")
    func outdated() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try folders.write("parts/4592.dat", in: folders.library, typeLine: "0 !LDRAW_ORG Part UPDATE 2022-01")
        try folders.write("parts/4592.dat", in: folders.overrides, typeLine: "0 !LDRAW_ORG Part UPDATE 2005-01")
        try folders.write("parts/2815.dat", in: folders.library, typeLine: "0 !LDRAW_ORG Part UPDATE 2012-01")
        try folders.write("parts/2815.dat", in: folders.overrides, typeLine: "0 !LDRAW_ORG Part UPDATE 2012-01")
        try folders.write("parts/s/56145s02.dat", in: folders.library, typeLine: "0 !LDRAW_ORG Subpart UPDATE 2023-05")
        try folders.write("parts/s/56145s02.dat", in: folders.overrides, typeLine: "0 !LDRAW_ORG Subpart ORIGINAL")
        try folders.write("p/48/x.dat", in: folders.library, typeLine: "0 !LDRAW_ORG 48_Primitive UPDATE 2020-01")
        try folders.write("p/48/x.dat", in: folders.overrides, typeLine: "0 !LDRAW_ORG Unofficial_48_Primitive")
        try folders.write("parts/mine.dat", in: folders.overrides, typeLine: "0 !LDRAW_ORG Part UPDATE 2001-01")
        try "not a part".write(to: folders.overrides.appendingPathComponent("parts/notes.txt"),
                               atomically: true, encoding: .utf8)

        let overrides = LDrawPartOverride.overrides(paths: folders.paths())
        let byName = Dictionary(uniqueKeysWithValues: overrides.map { ($0.partName, $0) })

        #expect(overrides.map(\.partName) == ["48\\x.dat", "2815.dat", "4592.dat", "mine.dat", "s\\56145s02.dat"])
        #expect(byName["4592.dat"]?.libraryIsNewer == true)
        #expect(byName["4592.dat"]?.update == "2005-01")
        #expect(byName["4592.dat"]?.libraryUpdate == "2022-01")
        #expect(byName["2815.dat"]?.libraryIsNewer == false)
        #expect(byName["s\\56145s02.dat"]?.libraryIsNewer == true)
        #expect(byName["48\\x.dat"]?.libraryIsNewer == false)
        #expect(byName["mine.dat"]?.libraryPath == nil)
        #expect(byName["mine.dat"]?.libraryIsNewer == false)
    }

    @Test("Files in deeper folders are listed by the name a part line gives them")
    func deeperFolders() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try FileManager.default.createDirectory(at: folders.overrides.appendingPathComponent("parts/48/s"),
                                                withIntermediateDirectories: true)
        try folders.write("parts/48/s/56145s01.dat", in: folders.overrides, typeLine: nil)
        try folders.write("parts/3001.dat", in: folders.overrides, typeLine: nil)

        let names = LDrawPartOverride.overrides(paths: folders.paths()).map(\.partName)
        #expect(names == ["48\\s\\56145s01.dat", "3001.dat"])
    }

    @Test("Hidden files and folders are not listed")
    func hiddenFiles() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try FileManager.default.createDirectory(at: folders.overrides.appendingPathComponent("parts/.old"),
                                                withIntermediateDirectories: true)
        try folders.write("parts/3001.dat", in: folders.overrides, typeLine: nil)
        try folders.write("parts/._3001.dat", in: folders.overrides, typeLine: nil)
        try folders.write("parts/.old/3002.dat", in: folders.overrides, typeLine: nil)

        #expect(LDrawPartOverride.overrides(paths: folders.paths()).map(\.partName) == ["3001.dat"])
    }

    @Test("The catalog lists leave out the parts only the overrides folder has while it is off")
    func catalogWhenOff() {
        let records: [[AnyHashable: Any]] = [[PART_NUMBER_KEY: "3001.dat"],
                                             [PART_NUMBER_KEY: "mine.dat", PART_ONLY_IN_OVERRIDES_KEY: true]]
        let names = { (records: [[AnyHashable: Any]]) in records.compactMap { $0[PART_NUMBER_KEY] as? String } }

        #expect(names(LDrawPartLibrary.partCatalogRecords(records, usingOverrides: true)) == ["3001.dat", "mine.dat"])
        #expect(names(LDrawPartLibrary.partCatalogRecords(records, usingOverrides: false)) == ["3001.dat"])
    }

    @Test("A category that no listed part is filed under is left out")
    func categoriesWhenOff() {
        let records: [[AnyHashable: Any]] = [[PART_NUMBER_KEY: "3001.dat", PART_CATEGORY_KEY: "Brick"],
                                             [PART_NUMBER_KEY: "3002.dat"]]

        #expect(LDrawPartLibrary.categories(["Brick", "My Fixes", "Plate"], usedBy: records) == ["Brick"])
    }

    @Test("No overrides folder lists nothing")
    func noFolder() throws {
        let folders = try Folders()
        defer { folders.remove() }

        #expect(LDrawPartOverride.overrides(paths: folders.paths(withOverrides: false)).isEmpty)
    }
}
