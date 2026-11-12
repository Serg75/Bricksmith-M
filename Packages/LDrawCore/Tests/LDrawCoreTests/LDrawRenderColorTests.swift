//
//  LDrawRenderColorTests.swift
//  LDrawCoreTests
//
//  Covers the color a renderer gets: its alpha carries a metallic finish, and
//  the alpha and the finish come apart again.
//
//  Created by Sergey Slobodenyuk on 2026-11-12.
//

import Testing
import Foundation
import LDrawCore

@Suite("The color a renderer draws")
struct LDrawRenderColorTests {

    static func color(alpha: Float, material: LDrawColorMaterialT, name: String = "Some_Color") -> LDrawColor {
        var rgba: [Float] = [0.25, 0.5, 0.75, alpha]
        let color = LDrawColor()

        color.setColorRGBA(&rgba)
        color.setMaterial(material)
        color.setName(name)
        return color
    }

    static func renderRGBA(_ color: LDrawColor) -> [Float] {
        var rgba = [Float](repeating: 0, count: 4)

        color.getRenderColorRGBA(&rgba)
        return rgba
    }

    @Test("A plain color is unchanged")
    func plainColorIsUnchanged() {
        let rgba = Self.renderRGBA(Self.color(alpha: 0.5, material: .none))

        #expect(rgba == [0.25, 0.5, 0.75, 0.5])
    }

    @Test("A metallic finish comes back out of the alpha",
          arguments: [(LDrawColorMaterialT.chrome, LDrawRenderMaterial.chrome),
                      (.pearlescent, .satinMetallic),
                      (.matteMetallic, .matteMetallic),
                      (.metal, .metal)],
          [Float(1.0), 0.5])
    func finishComesBackOut(finish: (LDrawColorMaterialT, LDrawRenderMaterial), alpha: Float) {
        let rgba = Self.renderRGBA(Self.color(alpha: alpha, material: finish.0))

        #expect(Array(rgba[0..<3]) == [0.25, 0.5, 0.75])
        #expect(LDrawRenderColorMaterial(rgba[3]) == finish.1.rawValue)
        #expect(LDrawRenderColorAlpha(rgba[3]) == alpha)
        #expect(LDrawRenderColorIsTranslucent(rgba[3]) == (alpha < 1))
    }

    @Test("A pearlescent color is smooth only when its name says Pearl",
          arguments: [("Pearl_Silver", LDrawRenderMaterial.pearlescent),
                      ("Flat_Silver", .satinMetallic),
                      ("Metallic_Blue", .satinMetallic)])
    func pearlescentGoesByName(name: String, finish: LDrawRenderMaterial) {
        #expect(Self.color(alpha: 1, material: .pearlescent, name: name).renderMaterial() == finish)
    }

    @Test("Rubber and custom finishes draw as plain colors",
          arguments: [LDrawColorMaterialT.rubber, .custom])
    func otherFinishesArePlain(material: LDrawColorMaterialT) {
        let rgba = Self.renderRGBA(Self.color(alpha: 1, material: material))

        #expect(rgba[3] == 1)
    }

    @Test("A meta color's alpha of 0 carries no finish")
    func metaAlphaStaysZero() {
        #expect(LDrawRenderColorPackAlpha(0, .chrome) == 0)
    }
}
