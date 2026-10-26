//
//  LDrawPartAvailabilityTests.swift
//  LDrawInventoryTests
//
//  Tests for the catalog of when parts came in which colors.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawInventory

@Suite("Part availability")
struct LDrawPartAvailabilityTests {

    private func record(_ availability: LDrawPartAvailability, _ part: String, _ color: Int)
        -> LDrawPartAvailabilityRecord? {
        var record = LDrawPartAvailabilityRecord()
        return availability.getRecord(&record, forPartNumber: part, colorID: color) ? record : nil
    }

    @Test("The builder keeps the first and last year and counts the sets")
    func builderYears() throws {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2015, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 4, year: 1999, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 4, year: 2026, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 0, year: 2010, inDatabaseSet: false)

        let availability = builder.availability(with: nil)
        let red = try #require(record(availability, "3001", 4))
        #expect(red.firstYear == 1999)
        #expect(red.lastYear == 2026)
        #expect(red.setCount == 3)
        #expect(red.onlyInDatabaseSets == false)
        #expect(record(availability, "3001", 1) == nil)
        #expect(record(availability, "3002", 4) == nil)
        #expect(availability.partCount == 1)
    }

    @Test("Real sets win over Database Sets; a pair only in them is flagged")
    func databaseSets() throws {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2024, inDatabaseSet: true)
        builder.notePartNumber("3001", colorID: 4, year: 2012, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 5, year: 2024, inDatabaseSet: true)

        let availability = builder.availability(with: nil)
        let real = try #require(record(availability, "3001", 4))
        #expect(real.lastYear == 2012)
        #expect(real.setCount == 1)
        #expect(real.onlyInDatabaseSets == false)

        let pickABrick = try #require(record(availability, "3001", 5))
        #expect(pickABrick.lastYear == 2024)
        #expect(pickABrick.onlyInDatabaseSets == true)
    }

    @Test("A catalog reads back what it wrote, date included")
    func roundTrip() throws {
        let builder = LDrawPartAvailabilityBuilder()
        builder.notePartNumber("3001", colorID: 4, year: 2020, inDatabaseSet: false)
        builder.notePartNumber("3001", colorID: 4, year: 2021, inDatabaseSet: false)
        builder.notePartNumber("3626cpr0001", colorID: 14, year: 2024, inDatabaseSet: true)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let written = builder.availability(with: date)
        let read = try #require(LDrawPartAvailability(dictionary: written.dictionaryRepresentation()))

        #expect(read.date == date)
        #expect(Set(read.partNumbers()) == ["3001", "3626cpr0001"])
        let red = try #require(record(read, "3001", 4))
        #expect(red.firstYear == 2020)
        #expect(red.lastYear == 2021)
        #expect(red.setCount == 2)
        #expect(try #require(record(read, "3626cpr0001", 14)).onlyInDatabaseSets == true)
    }

    @Test("Rows that do not read are skipped; no parts table is nil")
    func junk() throws {
        let read = try #require(LDrawPartAvailability(dictionary: [
            "version": 7,
            "parts": ["3001": [[4, 2000, 2020, 3], [5, 2000], "junk"], "3002": "junk"],
        ]))
        #expect(read.partNumbers() == ["3001"])
        #expect(record(read, "3001", 4)?.setCount == 3)
        #expect(record(read, "3001", 5) == nil)
        #expect(LDrawPartAvailability(dictionary: ["version": 1]) == nil)
    }

    @Test("Each color of a part is enumerated once")
    func enumeration() {
        let builder = LDrawPartAvailabilityBuilder()
        for color in [0, 4, 4, 15] {
            builder.notePartNumber("3001", colorID: color, year: 2020, inDatabaseSet: false)
        }
        var colors: [Int] = []
        builder.availability(with: nil).enumerateRecords(forPartNumber: "3001") { colors.append($0.colorID) }
        #expect(colors.sorted() == [0, 4, 15])
    }
}
