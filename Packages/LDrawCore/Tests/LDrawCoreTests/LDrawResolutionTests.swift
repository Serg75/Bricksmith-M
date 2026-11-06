//
//  LDrawResolutionTests.swift
//  UnitTests
//
//  Tests for drawing the high or low version of a part: which file a name
//  finds, and how high versions in the overrides folder are checked.
//
//  Created by Sergey Slobodenyuk on 2026-11-06.
//

import Testing
import Foundation
import LDrawCore

@Suite("The resolution of parts")
struct LDrawResolutionTests {

    /// A library and an overrides folder in a new temporary folder.
    private struct Folders {
        let root: URL
        let library: URL
        let overrides: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LDrawResolutionTests-\(UUID().uuidString)")
            library = root.appendingPathComponent("ldraw")
            overrides = root.appendingPathComponent("overrides")
            for (folder, subs) in [(library, ["parts/s", "p/48", "p/8"]), (overrides, ["parts/48/s", "p/48"])] {
                for sub in subs {
                    try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub),
                                                            withIntermediateDirectories: true)
                }
            }
            try write("parts/56145.dat", in: library, ["0 Wheel", "1 16 0 0 0 1 0 0 0 1 0 0 0 1 s\\54087s00.dat",
                                                       "1 16 0 0 0 1 0 0 0 1 0 0 0 1 4-4cyli.dat"])
            try write("parts/s/54087s00.dat", in: library, ["0 ~Outer", "0 !LDRAW_ORG Subpart UPDATE 2023-05"])
            try write("p/4-4cyli.dat", in: library, ["0 Cylinder"])
            try write("p/48/4-4cyli.dat", in: library, ["0 Hi-Res Cylinder"])
            try write("p/8/4-4cyli.dat", in: library, ["0 Lo-Res Cylinder"])
            try write("p/4-4disc.dat", in: library, ["0 Disc"])
            try write("parts/48/s/54087s00.dat", in: overrides, ["0 ~Outer", "0 !LDRAW_ORG Subpart UPDATE 2012-02"])
        }

        func write(_ path: String, in folder: URL, _ lines: [String]) throws {
            try lines.joined(separator: "\r\n")
                .write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        func paths(_ resolution: LDrawResolution) -> LDrawPaths {
            let paths = LDrawPaths()
            paths.setPreferredLDrawPath(library.path)
            paths.setOverridesPath(overrides.path)
            paths.setResolution(resolution)
            return paths
        }

        func path(_ folder: URL, _ relative: String) -> String {
            folder.appendingPathComponent(relative).path
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("High finds the 48 version, Low the 8 version, and Normal the part itself")
    func versions() throws {
        let folders = try Folders()
        defer { folders.remove() }

        let normal = folders.path(folders.library, "p/4-4cyli.dat")
        let high = folders.path(folders.library, "p/48/4-4cyli.dat")
        let low = folders.path(folders.library, "p/8/4-4cyli.dat")

        #expect(folders.paths(.normal).path(forPartName: "4-4cyli.dat") == normal)
        #expect(folders.paths(.high).path(forPartName: "4-4cyli.dat") == high)
        #expect(folders.paths(.low).path(forPartName: "4-4cyli.dat") == low)
    }

    @Test("A resolution that is none of the three is Normal")
    func unknownResolution() throws {
        let folders = try Folders()
        defer { folders.remove() }
        let paths = folders.paths(.high)

        paths.setResolution(try #require(LDrawResolution(rawValue: 3)))

        #expect(paths.resolution() == .normal)
        #expect(paths.path(forPartName: "4-4cyli.dat") == folders.path(folders.library, "p/4-4cyli.dat"))
    }

    @Test("A part with no other version is itself, and a name that names a version is kept")
    func fallbacks() throws {
        let folders = try Folders()
        defer { folders.remove() }

        #expect(folders.paths(.high).path(forPartName: "4-4disc.dat") == folders.path(folders.library, "p/4-4disc.dat"))
        #expect(folders.paths(.low).path(forPartName: "48\\4-4cyli.dat")
                == folders.path(folders.library, "p/48/4-4cyli.dat"))
    }

    @Test("A high version of a subpart in the overrides folder is used in High only")
    func highSubpart() throws {
        let folders = try Folders()
        defer { folders.remove() }
        let high = folders.paths(.high)

        #expect(high.path(forPartName: "s\\54087s00.dat") == folders.path(folders.overrides, "parts/48/s/54087s00.dat"))
        #expect(folders.paths(.normal).path(forPartName: "s\\54087s00.dat")
                == folders.path(folders.library, "parts/s/54087s00.dat"))
        #expect(high.path(forPartName: "s\\54087s00.dat", usingOverrides: false)
                == folders.path(folders.library, "parts/s/54087s00.dat"))
        #expect(high.libraryPath(forPartName: "4-4cyli.dat") == folders.path(folders.library, "p/4-4cyli.dat"))
    }

    @Test("A fix of a primitive is used in High and Low, though the library has its versions")
    func fixAtEveryResolution() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try folders.write("p/4-4cyli.dat", in: folders.overrides, ["0 Fixed Cylinder"])
        let fix = folders.path(folders.overrides, "p/4-4cyli.dat")

        #expect(folders.paths(.high).path(forPartName: "4-4cyli.dat") == fix)
        #expect(folders.paths(.low).path(forPartName: "4-4cyli.dat") == fix)
        #expect(folders.paths(.high).path(forPartName: "4-4cyli.dat", usingOverrides: false)
                == folders.path(folders.library, "p/48/4-4cyli.dat"))
    }

    @Test("A high version added later is found after the folder is turned off and on")
    func addedHighVersion() throws {
        let folders = try Folders()
        defer { folders.remove() }
        let high = folders.paths(.high)

        #expect(high.path(forPartName: "4-4disc.dat") == folders.path(folders.library, "p/4-4disc.dat"))
        try folders.write("p/48/4-4disc.dat", in: folders.overrides, ["0 Hi-Res Disc"])
        high.setOverridesEnabled(false)
        high.setOverridesEnabled(true)

        #expect(high.path(forPartName: "4-4disc.dat") == folders.path(folders.overrides, "p/48/4-4disc.dat"))
    }

    @Test("A high version the library lacks is checked against the part itself")
    func outdatedHighVersion() throws {
        let folders = try Folders()
        defer { folders.remove() }
        let overrides = LDrawPartOverride.overrides(paths: folders.paths(.normal))
        let high = try #require(overrides.first { $0.partName == "48\\s\\54087s00.dat" })

        #expect(high.libraryPath == folders.path(folders.library, "parts/s/54087s00.dat"))
        #expect(high.update == "2012-02")
        #expect(high.libraryUpdate == "2023-05")
        #expect(high.libraryIsNewer)
    }
}
