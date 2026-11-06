//
//  LDrawPartComparisonTests.swift
//  UnitTests
//
//  Tests for the two sides of a part, for turning the overrides folder off,
//  and for finding the loaded parts an override changes. No part library is
//  registered, since other suites in the same run check what happens without
//  one.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//

import Testing
import Foundation
import LDrawCore

@Suite("Comparing a part with the library", .serialized)
struct LDrawPartComparisonTests {

    /// A library and an overrides folder in a new temporary folder.
    private struct Folders {
        let root: URL
        let library: URL
        let overrides: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LDrawPartComparisonTests-\(UUID().uuidString)")
            library = root.appendingPathComponent("ldraw")
            overrides = root.appendingPathComponent("overrides")
            for folder in [library, overrides] {
                for sub in ["parts/s", "p/48"] {
                    try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub),
                                                            withIntermediateDirectories: true)
                }
            }
        }

        func write(_ path: String, in folder: URL, _ lines: [String]) throws {
            try lines.joined(separator: "\r\n")
                .write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        func paths() -> LDrawPaths {
            let paths = LDrawPaths()
            paths.setPreferredLDrawPath(library.path)
            paths.setOverridesPath(overrides.path)
            return paths
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func use(_ name: String) -> String {
        "1 16 0 0 0 1 0 0 0 1 0 0 0 1 \(name)"
    }

    /// A wheel whose rim subpart is overridden, and a brick that uses nothing
    /// overridden.
    private func wheelFolders() throws -> Folders {
        let folders = try Folders()
        try folders.write("parts/56145.dat", in: folders.library,
                          ["0 Wheel", Self.use("s\\56145s02.dat"), Self.use("stud.dat")])
        try folders.write("parts/s/56145s02.dat", in: folders.library,
                          ["0 ~Rim", "3 16 0 0 0 1 0 0 0 1 0"])
        try folders.write("p/stud.dat", in: folders.library, ["0 Stud", "2 24 0 0 0 1 0 0"])
        try folders.write("parts/3001.dat", in: folders.library, ["0 Brick", Self.use("stud.dat")])
        try folders.write("parts/s/56145s02.dat", in: folders.overrides,
                          ["0 FILE ~Rim High.ldr", "0 ~Rim High", Self.use("subpart.ldr"),
                           "0 FILE subpart.ldr", "0 Piece", "3 16 0 0 0 2 0 0 0 2 0"])
        return folders
    }

    @Test("Turning the folder off finds the library's part, and the asked side is found either way")
    func turningOff() throws {
        let folders = try wheelFolders()
        defer { folders.remove() }
        let paths = folders.paths()
        let override = folders.overrides.appendingPathComponent("parts/s/56145s02.dat").path
        let library = folders.library.appendingPathComponent("parts/s/56145s02.dat").path

        #expect(paths.overridesEnabled())
        #expect(paths.path(forPartName: "s\\56145s02.dat") == override)
        paths.setOverridesEnabled(false)
        #expect(paths.path(forPartName: "s\\56145s02.dat") == library)
        #expect(paths.path(forPartName: "s\\56145s02.dat", usingOverrides: true) == override)
        #expect(paths.overridesPath() == folders.overrides.path)
    }

    @Test("A part that uses an overridden subpart lists it as changed")
    func changedNames() throws {
        let folders = try wheelFolders()
        defer { folders.remove() }

        let wheel = LDrawPartComparison(partName: "56145.dat", paths: folders.paths())
        let brick = LDrawPartComparison(partName: "3001.dat", paths: folders.paths())

        #expect(wheel.changedPartNames == ["s\\56145s02.dat"])
        #expect(brick.changedPartNames.isEmpty)
        #expect(wheel.libraryPath == folders.library.appendingPathComponent("parts/56145.dat").path)
    }

    @Test("Each side holds its own files on the way to the override, and nothing else")
    func sideLines() throws {
        let folders = try wheelFolders()
        defer { folders.remove() }
        let comparison = LDrawPartComparison(partName: "56145.dat", paths: folders.paths())

        let library = comparison.lines(usingOverrides: false)
        #expect(library == ["0 FILE 56145.dat", "0 Wheel", Self.use("s\\56145s02.dat"), Self.use("stud.dat"),
                            "0 FILE s\\56145s02.dat", "0 ~Rim", "3 16 0 0 0 1 0 0 0 1 0"])

        let override = comparison.lines(usingOverrides: true)
        #expect(override == ["0 FILE 56145.dat", "0 Wheel", Self.use("s\\56145s02.dat"), Self.use("stud.dat"),
                             "0 FILE s\\56145s02.dat", "0 ~Rim High", Self.use("s\\56145s02.dat#subpart.ldr"),
                             "0 FILE s\\56145s02.dat#subpart.ldr", "0 Piece", "3 16 0 0 0 2 0 0 0 2 0"])
    }

    @Test("A side's file has the part first and finds the overridden part inside itself")
    func parsedSide() throws {
        let folders = try wheelFolders()
        defer { folders.remove() }
        let file = LDrawPartComparison(partName: "56145.dat", paths: folders.paths()).file(usingOverrides: false)

        #expect(file.firstModel().modelName() == "56145.dat")
        #expect(file.model(withName: "s\\56145s02.dat") != nil)
        #expect(file.modelNames().count == 2)
    }

    @Test("A part only the overrides folder has is an empty model on the library side")
    func missingOnLibrarySide() throws {
        let folders = try wheelFolders()
        defer { folders.remove() }
        try folders.write("parts/mine.dat", in: folders.overrides, ["0 Mine", Self.use("stud.dat")])
        let comparison = LDrawPartComparison(partName: "mine.dat", paths: folders.paths())

        #expect(comparison.changedPartNames == ["mine.dat"])
        #expect(comparison.libraryPath == nil)
        #expect(comparison.lines(usingOverrides: false) == ["0 FILE mine.dat", "0 ~Missing"])
    }

    @Test("The parts to read again are the changed ones and every part that uses one, however deep")
    func partsToForget() {
        let uses: [String: Set<String>] = ["56145.dat": ["s\\56145s02.dat", "stud.dat"],
                                           "s\\56145s02.dat": ["48\\t01q1429.dat"],
                                           "3001.dat": ["stud.dat"],
                                           "stud.dat": []]

        #expect(LDrawPartLibrary.partNames(using: ["48\\t01q1429.dat"], uses: uses)
                == ["48\\t01q1429.dat", "s\\56145s02.dat", "56145.dat"])
        #expect(LDrawPartLibrary.partNames(using: ["stud.dat"], uses: uses)
                == ["stud.dat", "56145.dat", "3001.dat"])
        #expect(LDrawPartLibrary.partNames(using: ["mine.dat"], uses: uses) == ["mine.dat"])
    }
}
