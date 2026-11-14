//
//  LDrawPartLibraryLastUpdateTests.swift
//  LDrawCoreTests
//
//  Tests for the category of the parts the LDraw folder's last update added,
//  and for the update stamped into the catalog.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//

import Testing
import Foundation
import LDrawCore

@Suite("Parts of the last update")
struct LDrawPartLibraryLastUpdateTests {

    private func library() -> LDrawPartLibrary {
        func record(_ name: String, _ category: String) -> [String: Any] {
            [PART_NUMBER_KEY: name, PART_NAME_KEY: name, PART_CATEGORY_KEY: category]
        }
        let catalog: [String: Any] = [
            PARTS_CATALOG_KEY: ["Brick": [[PART_NUMBER_KEY: "3001.dat"], [PART_NUMBER_KEY: "99999.dat"]]],
            PARTS_LIST_KEY: [
                "3001.dat": record("3001.dat", "Brick"),
                "99999.dat": record("99999.dat", "Brick"),
                "88888.dat": record("88888.dat", Category_Moved),
                "77777.dat": record("77777.dat", Category_Alias),
            ],
            VERSION_KEY: "1",
        ]

        let library = LDrawPartLibrary()
        library.setPartCatalog(catalog)
        return library
    }

    private func libraryItems(of library: LDrawPartLibrary) -> [String] {
        let groups = library.categoryHierarchy() as? [[String: Any]] ?? []
        let children = groups.first?[CategoryChildrenKey] as? [[String: Any]] ?? []
        return children.compactMap { $0[CategoryNameKey] as? String }
    }

    @Test("The added parts the catalog has are a category with the host's title")
    func category() {
        let library = library()
        library.setPartNamesFromLastUpdate(["99999.dat", "88888.dat", "77777.dat", "gone.dat"], title: "New in 2026-11")

        let records = library.partCatalogRecords(inCategory: Category_LastUpdate) as? [[String: Any]]
        #expect(records?.compactMap { $0[PART_NUMBER_KEY] as? String } == ["99999.dat"])
        #expect(library.displayName(forCategory: Category_LastUpdate) == "New in 2026-11")
        #expect(libraryItems(of: library) == [Category_All, Category_Favorites, Category_LastUpdate])
    }

    @Test("With no added part in the catalog there is no such category")
    func noCategory() {
        let library = library()
        #expect(library.partCatalogRecords(inCategory: Category_LastUpdate).isEmpty)
        #expect(libraryItems(of: library) == [Category_All, Category_Favorites])

        library.setPartNamesFromLastUpdate(["88888.dat", "gone.dat"], title: "New in 2026-11")
        #expect(library.partCatalogRecords(inCategory: Category_LastUpdate).isEmpty)
        #expect(libraryItems(of: library) == [Category_All, Category_Favorites])
    }

    @Test("A saved catalog of another update of the folder is scanned again, if the folder can save it")
    func catalogRelease() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LDrawPartLibraryLastUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let stamped: [String: Any] = [VERSION_KEY: "1", LIBRARY_RELEASE_KEY: "2026-10"]
        let unstamped: [String: Any] = [VERSION_KEY: "1"]
        func needsScan(_ catalog: [String: Any], _ release: String?) -> Bool {
            LDrawPartLibrary.catalogNeedsScan(catalog, forRelease: release, folderPath: folder.path)
        }

        #expect(needsScan(stamped, "2026-10") == false)
        #expect(needsScan(unstamped, nil) == false)
        #expect(needsScan(stamped, "2026-11"))
        #expect(needsScan(stamped, nil))
        #expect(needsScan(unstamped, "2026-10"))
        #expect(needsScan([VERSION_KEY: "1", LIBRARY_RELEASE_KEY: 2610], "2026-10"))

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(needsScan(unstamped, "2026-10") == false)
    }
}
