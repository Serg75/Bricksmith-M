//
//  LDrawRebrickableCSVReaderTests.swift
//  LDrawRebrickableTests
//
//  Tests for reading CSV files, gzipped or not.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawRebrickable

@Suite("CSV reader")
struct LDrawRebrickableCSVReaderTests {

    private func rows(_ name: String) throws -> (columns: [String], rows: [[String]]) {
        let reader = try LDrawRebrickableCSVReader(url: RebrickableFixtures.root.appendingPathComponent(name))
        var rows: [[String]] = []
        try reader.enumerateRows { fields, _ in rows.append(fields) }
        return (reader.columnNames, rows)
    }

    @Test("Quotes, doubled quotes, commas and line breaks in fields read right; blank lines are skipped")
    func quoting() throws {
        let file = try rows("plain.csv")
        #expect(file.columns == ["a", "b", "c"])
        #expect(file.rows == [["1", "two, with comma", "3"],
                              ["say \"hi\"", "", "line\nbreak"],
                              ["4", "5"]])
    }

    @Test("A gzipped file reads, CR LF line ends and quoted numbers included")
    func gzip() throws {
        let file = try rows("downloads/inventory_parts.csv.gz")
        #expect(file.columns == ["inventory_id", "part_num", "color_id", "quantity", "is_spare", "img_url"])
        #expect(file.rows.count == 13)
        #expect(file.rows[11] == ["6", "3003", "4", "2", "f", ""])
    }

    @Test("A file of two gzip members reads as one")
    func members() throws {
        let file = try rows("members.csv.gz")
        #expect(file.columns == ["a", "b"])
        #expect(file.rows == [["1", "2"], ["3", "4"]])
    }

    @Test("A file cut off partway is an error")
    func truncated() throws {
        #expect(throws: (any Error).self) {
            let url = RebrickableFixtures.root.appendingPathComponent("truncated.csv.gz")
            let reader = try LDrawRebrickableCSVReader(url: url)
            try reader.enumerateRows { _, _ in }
        }
    }

    @Test("A missing file, or a missing column, is an error")
    func missing() throws {
        #expect(throws: (any Error).self) {
            _ = try LDrawRebrickableCSVReader(url: RebrickableFixtures.root.appendingPathComponent("nothing.csv"))
        }
        let reader = try LDrawRebrickableCSVReader(url: RebrickableFixtures.root.appendingPathComponent("plain.csv"))
        #expect(try reader.indexes(ofColumns: ["c", "a"]) == [2, 0])
        #expect(throws: (any Error).self) { try reader.indexes(ofColumns: ["a", "z"]) }
    }

    @Test("Reading stops when the block asks")
    func stopping() throws {
        let reader = try LDrawRebrickableCSVReader(url: RebrickableFixtures.root.appendingPathComponent("plain.csv"))
        var count = 0
        try reader.enumerateRows { _, stop in
            count += 1
            stop.pointee = true
        }
        #expect(count == 1)
    }
}
