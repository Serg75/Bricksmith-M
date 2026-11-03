//
//  LDrawInventoryPartsFileTests.swift
//  LDrawInventoryTests
//
//  Tests for reading loose parts from parts list files.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory

@Suite("Parts list files")
struct LDrawInventoryPartsFileTests {

    @Test("Bricksmith's piece count export reads as LDraw parts, header skipped, repeats added up")
    func pieceCountExport() throws {
        let text = "Quantity\tPart\tColor\tDescription\n"
            + "6\t3001\t4\tBrick  2 x  4\n"
            + "2\t3001.dat\t4\tBrick  2 x  4\n"
            + "1\t3626CP01\t14\tMinifig Head with Face\n"
        let items = try LDrawInventoryPartsFile.items(from: text)

        #expect(items.count == 2)
        #expect(items[0].ldrawPartName == "3001.dat")
        #expect(items[0].ldrawColorCode.rawValue == 4)
        #expect(items[0].quantity == 8)
        #expect(items[0].rebrickablePartNumber == nil)
        #expect(items[1].ldrawPartName == "3626cp01.dat")
    }

    @Test("A Rebrickable CSV reads as Rebrickable parts, with spares and quoted fields")
    func rebrickableCSV() throws {
        let text = "Part,Color,Quantity,Is Spare\r\n"
            + "3001,4,6,False\r\n"
            + "\"3001\",4,1,True\r\n"
            + "\"973pr1,x\",15,2,False\r\n"
        let items = try LDrawInventoryPartsFile.items(from: text)

        #expect(items.count == 2)
        #expect(items[0].rebrickablePartNumber == "3001")
        #expect(items[0].rebrickableColorID == 4)
        #expect(items[0].quantity == 6)
        #expect(items[0].spareQuantity == 1)
        #expect(items[0].ldrawPartName == nil)
        #expect(items[1].rebrickablePartNumber == "973pr1,x")
    }

    @Test("Text in neither format is an error")
    func unknownFormat() {
        #expect(throws: (any Error).self) { try LDrawInventoryPartsFile.items(from: "<INVENTORY></INVENTORY>") }
        #expect(throws: (any Error).self) { try LDrawInventoryPartsFile.items(from: "Name,Count\nfoo,1") }
        #expect(throws: (any Error).self) { try LDrawInventoryPartsFile.items(from: "") }
    }
}
