//
//  LDrawRebrickableLiveTests.swift
//  LDrawRebrickableTests
//
//  Downloads Rebrickable's real files and checks the catalog and two set
//  imports against them. Runs only when REBRICKABLE_LIVE_FOLDER names a folder
//  to download into; LDRAW_PART_CATALOG may name an "LDraw Parts.plist" to
//  measure how well the data matches an LDraw library. Prints what it finds.
//
//      REBRICKABLE_LIVE_FOLDER=/tmp/rb LDRAW_PART_CATALOG=".../LDraw Parts.plist" \
//          swift test --filter LDrawRebrickableLiveTests
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory
import LDrawRebrickable

private let environment = ProcessInfo.processInfo.environment

@Suite("Live Rebrickable data", .enabled(if: environment["REBRICKABLE_LIVE_FOLDER"] != nil))
struct LDrawRebrickableLiveTests {

    private let folder = URL(fileURLWithPath: environment["REBRICKABLE_LIVE_FOLDER"] ?? "/nonexistent")

    private func report(_ line: String) {
        print("LIVE: \(line)")
    }

    private func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "-" : String(format: "%.1f%%", 100 * Double(part) / Double(whole))
    }

    /// The part library's records, keyed by part name, or nil without a catalog.
    private func libraryRecords() -> [String: [String: Any]]? {
        guard let path = environment["LDRAW_PART_CATALOG"],
              let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let parts = plist[PARTS_LIST_KEY] as? [String: [String: Any]] else { return nil }
        return parts
    }

    @Test("Download, build the catalog, import two sets, and match them to the library")
    func liveRun() async throws {
        let downloads = LDrawRebrickableDownloads(folderURL: folder)
        let names = LDrawRebrickableDownloads.catalogFileNames()

        let started = Date()
        let (changed, error): ([String], Error?) = await withCheckedContinuation { continuation in
            _ = downloads.updateFiles(named: names, force: false, completionQueue: DispatchQueue(label: "live")) {
                continuation.resume(returning: ($0, $1))
            }
        }
        #expect(error == nil, "\(String(describing: error))")
        report("downloaded \(changed.count) of \(names.count) files in \(Int(Date().timeIntervalSince(started))) s")

        let building = Date()
        let catalog = try LDrawRebrickableCatalog(downloads: downloads)
        report(String(format: "catalog built in %.1f s: %d parts with records, %d known parts, %d relations, %d sets",
                      Date().timeIntervalSince(building), catalog.availability.partCount,
                      catalog.knownPartNumbers.count, catalog.relations.count, catalog.setList.count))
        report("data date \(String(describing: catalog.availability.date))")

        let storeFolder = folder.appendingPathComponent("store")
        try catalog.save(into: LDrawInventoryStore(folderURL: storeFolder),
                         colorLinks: LDrawRebrickableColors.builtInColorLinks())

        // What the app does at launch: read the saved catalog back.
        let reading = Date()
        let store = LDrawInventoryStore(folderURL: storeFolder)
        let saved = try #require(store.availability())
        let catalogBytes = (try? FileManager.default.attributesOfItem(
            atPath: storeFolder.appendingPathComponent("catalog.json").path)[.size] as? Int) ?? 0
        report(String(format: "saved catalog: %.1f MB, read back in %.2f s, %d parts",
                      Double(catalogBytes) / 1_000_000, Date().timeIntervalSince(reading), saved.partCount))

        let records = libraryRecords()
        let identity = store.identity(withCatalogRecords: records.map { Array($0.values) })

        for number in ["42115-1", "10295-1"] {
            let importing = Date()
            let set = try LDrawRebrickableSetImporter.setInventory(number: number, downloads: downloads,
                                                                  setList: catalog.setList)
            report(String(format: "%@ \"%@\" (%d): %d items, %d parts + %d spares, imported in %.1f s",
                          set.setNumber, set.name, set.year, set.items.count, set.partCount, set.spareCount,
                          Date().timeIntervalSince(importing)))
            #expect(set.items.count > 0)

            guard let records else { continue }
            var matchedItems = 0, matchedPieces = 0, coloredPieces = 0, pieces = 0
            var misses: [String] = []
            for item in set.items {
                let partName = identity.partName(forRebrickablePartNumber: item.rebrickablePartNumber ?? "")
                let hasPart = records[partName] != nil
                let hasColor = identity.colorCode(forRebrickableColorID: item.rebrickableColorID).rawValue != -1
                pieces += Int(item.quantity)
                if hasPart { matchedItems += 1; matchedPieces += Int(item.quantity) }
                if hasColor { coloredPieces += Int(item.quantity) }
                if !hasPart { misses.append(item.rebrickablePartNumber ?? "?") }
            }
            report("\(set.setNumber): LDraw part found for \(percent(matchedItems, set.items.count)) of items, "
                   + "\(percent(matchedPieces, pieces)) of pieces; color linked for \(percent(coloredPieces, pieces)) of pieces")
            report("\(set.setNumber): no LDraw part for \(misses.prefix(25).joined(separator: ", "))")
        }

        guard let records else { return }
        let table = store.table(for: LDrawPartLimit.availableNow(), identity: identity, year: 2026)
        let anyYear = LDrawPartLimit.availableNow().mutableCopy() as! LDrawMutablePartLimit
        anyYear.yearsBack = 0
        let everTable = store.table(for: anyYear.copy() as! LDrawPartLimit, identity: identity, year: 2026)

        let skipped: Set<String> = [Category_Alias, Category_Moved, Category_Primitives, Category_Subparts]
        let parts = records.values.filter { !skipped.contains($0[PART_CATEGORY_KEY] as? String ?? "") }
        var known = 0, made = 0, now = 0
        for record in parts {
            guard let name = record[PART_NUMBER_KEY] as? String else { continue }
            if identity.rebrickablePartNumber(forPartName: name) != nil { known += 1 }
            if everTable.allowsPartNamed(name) { made += 1 }
            if table.allowsPartNamed(name) { now += 1 }
        }
        report("library: \(parts.count) parts; Rebrickable knows \(percent(known, parts.count)), "
               + "ever made \(percent(made, parts.count)), made in 2025–2026 \(percent(now, parts.count))")
        report("colors some part is made in now: \(table.allowedColorCodes()?.count ?? 0)")
    }
}
