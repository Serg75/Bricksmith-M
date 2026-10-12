//
//  LDrawStepCalloutFixtures.swift
//  LDrawStepEditingTests
//
//  A callout of a submodel, laid out as a box, for the tests of what a host
//  does with one.
//
//  The directives are built in memory. Their parts name no file, so nothing is
//  loaded from a part library.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//

import Testing
import Foundation
import LDrawCore
import LDrawFeatures

/// A file whose main model calls out sub.ldr in its one step. The caller keeps
/// the file, which owns the models.
struct CalloutFixture {

    let file = LDrawFile()
    let main = LDrawMPDModel.model() as! LDrawMPDModel
    let sub = LDrawMPDModel.model() as! LDrawMPDModel
    let step: LDrawStep

    static let page = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 1000, height: 800))
    static let assembly = Box2(origin: Point2(x: 400, y: 300), size: Size2(width: 200, height: 100))

    /// `stepCount` is how many steps build sub.ldr. `lines` go inside the
    /// callout, after its placement.
    init(stepCount: Int = 1, lines: [LDrawDirective] = []) {
        main.setModelName("main.ldr")
        file.addSubmodel(main)
        sub.setModelName("sub.ldr")
        file.addSubmodel(sub)

        for _ in 0..<stepCount {
            sub.addStep().add(CalloutFixture.part("3003.dat") as LDrawDirective)
        }

        step = main.addStep()

        let handedOver: LPubCalloutPliPerStep = CalloutFixture.lpub("CALLOUT PLI PER_STEP FALSE")
        let begin: LPubCallout = CalloutFixture.lpub("CALLOUT BEGIN")
        let end: LPubCallout = CalloutFixture.lpub("CALLOUT END")

        for directive in [handedOver, begin, CalloutFixture.part("sub.ldr")] + lines + [end] {
            step.add(directive)
        }
    }

    static func part(_ name: String) -> LDrawPart {
        let color = LDrawColor()
        color.setColorCode(LDrawColorT(rawValue: 4)!)

        let part = LDrawPart()
        part.setDisplayName(name, parse: false, in: nil)
        part.setLDrawColor(color)
        return part
    }

    static func lpub<Command: LPubCommand>(_ text: String) -> Command {
        let command = Command()
        command.lPubCommandString = text
        return command
    }

    /// Parses the text, so the line gets the class the file would give it.
    static func parsed(_ text: String) -> LDrawDirective {
        let lines = ["0 !LPUB " + text, "0 STEP"]
        let step = LDrawStep(lines: lines, in: NSRange(location: 0, length: lines.count), parentGroup: nil)

        return (step!.subdirectives() as! [LDrawDirective])[0]
    }

    var callout: LDrawStepCallout {
        get throws { try #require(LDrawStepCallout.callouts(forStep: step).first) }
    }

    /// The callout's box, laid out again from the file. On the page it goes
    /// against the assembly. Off the page the boxes are stacked.
    func box(onPage: Bool = true) throws -> LDrawStepCalloutBox {
        let metrics = LDrawStepPartListLayout.defaultMetrics()
        let nothing = Box2(origin: Point2(x: 0, y: 0), size: Size2(width: 0, height: 0))
        let options = LDrawStepCalloutBoxOptions(metrics: metrics,
                                                 assemblyScale: metrics.baseScale,
                                                 hostRect: CalloutFixture.page,
                                                 listFrame: nothing,
                                                 assemblyRect: CalloutFixture.assembly,
                                                 pointsPerPageInch: onPage ? 100 : 0,
                                                 listViewTransform: IdentityMatrix4,
                                                 showsLists: true)

        return try #require(LDrawStepCalloutBox.boxes(forCallouts: LDrawStepCallout.callouts(forStep: step),
                                                      inModel: main,
                                                      options: options).first)
    }

    /// A step's lines, short enough to read: a part by its name, an LPub line
    /// by its text.
    static func lines(of step: LDrawStep) -> [String] {
        (step.subdirectives() as! [LDrawDirective]).map { directive in
            if let part = directive as? LDrawPart {
                return part.referenceName()
            }
            if let command = directive as? LPubCommand {
                return command.lPubCommandString
            }
            return String(describing: type(of: directive))
        }
    }
}

func middle(of box: Box2) -> Point2 {
    Point2(x: box.origin.x + box.size.width / 2, y: box.origin.y + box.size.height / 2)
}
