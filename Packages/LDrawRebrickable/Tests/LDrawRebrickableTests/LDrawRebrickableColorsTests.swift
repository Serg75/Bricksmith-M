//
//  LDrawRebrickableColorsTests.swift
//  LDrawRebrickableTests
//
//  Tests for the color table shipped with the package.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//

import Testing
import Foundation
import LDrawCore
import LDrawInventory
import LDrawRebrickable

@Suite("Color table")
struct LDrawRebrickableColorsTests {

    @Test("The shipped table loads, and says how it was made")
    func builtIn() {
        let links = LDrawRebrickableColors.builtInColorLinks()
        #expect(links.count > 150)
        #expect(["api", "names"].contains(LDrawRebrickableColors.builtInTableSource() ?? ""))
    }

    @Test("Common colors link to their LDraw codes, the clashing ids included")
    func commonColors() {
        let links = LDrawRebrickableColors.builtInColorLinks()
        #expect(links[0]?.first == 0)       // Black
        #expect(links[4]?.first == 4)       // Red
        #expect(links[71]?.first == 71)     // Light Bluish Gray
        #expect(links[379]?.first == 379)   // Sand Blue
        #expect(links[326]?.first == 330)   // Olive Green, which is not LDraw's 326
        #expect(links[158]?.first == 326)   // Yellowish Green, which LDraw numbers 326
        #expect(links[9999] == nil)
    }

    @Test("A rubber color reads as its plain Rebrickable color")
    func rubber() {
        let data = LDrawPartIdentity.rebrickableData(withPartLinks: nil,
                                                     colorLinks: LDrawRebrickableColors.builtInColorLinks(),
                                                     relations: nil, knownPartNumbers: nil)
        let identity = LDrawPartIdentity(catalogRecords: nil, rebrickableData: data, overrides: nil)
        #expect(identity.rebrickableColorIDs(forColorCode: LDrawColorT(rawValue: 256)!) == [0])
        #expect(identity.colorCode(forRebrickableColorID: 0).rawValue == 0)
    }
}
