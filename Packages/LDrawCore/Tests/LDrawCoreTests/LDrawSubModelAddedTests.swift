//
//  LDrawSubModelAddedTests.swift
//  UnitTests
//
//  Tests for the notification a file posts when a model is added to it.
//
//  Created by Sergey Slobodenyuk on 2026-11-27.
//

import Testing
import Foundation
import LDrawCore

@Suite("The notification that a model was added")
struct LDrawSubModelAddedTests {

    /// The names the file's notifications carry while the block runs; nil for one without a name.
    private func namesPosted(by file: LDrawFile, while run: () -> Void) -> [String?] {
        let heard = NSMutableArray()
        let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(LDrawMPDSubModelAdded),
                                                              object: file, queue: nil) { notification in
            heard.add(notification.userInfo?[LDrawMPDSubModelAddedNameKey] ?? NSNull())
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        run()
        return heard.map { $0 as? String }
    }

    @Test("It carries the model's name in lowercase")
    func carriesName() throws {
        let file = LDrawFile()
        let model = try #require(LDrawMPDModel.model() as? LDrawMPDModel)

        model.setModelName("Wheel Assembly.ldr")
        #expect(namesPosted(by: file) { file.addSubmodel(model) } == ["wheel assembly.ldr"])
    }

    @Test("A model without a name is posted without one")
    func noName() throws {
        let file = LDrawFile()
        let model = try #require(LDrawMPDModel.model() as? LDrawMPDModel)

        model.setModelName("")
        #expect(namesPosted(by: file) { file.addSubmodel(model) } == [nil])
    }
}
