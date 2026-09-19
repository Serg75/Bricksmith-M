//
//  LDrawMetaCommandTests.swift
//  LDrawCoreTests
//
//  Which class a type 0 line becomes, and how a meta command is archived and
//  copied.
//
//  Created by Sergey Slobodenyuk on 2023-03-12.
//

import Testing
import Foundation
import LDrawCore

@Suite("Meta commands")
struct LDrawMetaCommandTests {

    @Test("The subclasses a type 0 line can become are found at run time")
    func subclassesAreFound() throws {
        let names: [String] = try #require(perform("subclassNames", on: LDrawMetaCommand.self))

        #expect(Set(names) == ["LDrawColor", "LDrawComment", "LDrawLSynthDirective", "LPubCommand"])
    }

    @Test("A line becomes the class its marker names", arguments: [
        ("  ", LDrawMetaCommand.self),
        ("", LDrawMetaCommand.self),
        ("0 some text", LDrawMetaCommand.self),
        ("0 !COLOUR name CODE 100 VALUE #F0F0F0 EDGE 400 ALPHA 0", LDrawColor.self),
        ("0 // comment", LDrawComment.self),
        ("0 !LPUB command", LPubCommand.self),
        ("0 !LPUB REMOVE GROUP \"a\"", LPubRemoveGroup.self),
    ] as [(String, AnyClass)])
    func lineBecomesItsClass(line: String, expected: AnyClass) throws {
        let command = try #require(LDrawMetaCommand(lines: [line], in: NSRange(location: 0, length: 1), parentGroup: nil))

        #expect(ObjectIdentifier(type(of: command)) == ObjectIdentifier(expected))
    }

    @Test("Only the command text is archived, and it reads back")
    func archiveRoundTrip() throws {
        let encoder = MockArchiver()
        let command = LDrawMetaCommand()
        command.commandString = "Some string"

        command.encode(with: encoder)

        #expect(encoder.data.count == 1)
        #expect(encoder.data["commandString"] as? String == "Some string")

        let decoded = try #require(LDrawMetaCommand(coder: encoder))
        #expect(decoded.commandString == "Some string")
    }

    @Test("A copy has the same text and is a separate object")
    func copyIsSeparate() throws {
        let command = LDrawMetaCommand()
        command.commandString = "Some string"

        let duplicate = try #require(command.copy() as? LDrawMetaCommand)
        #expect(duplicate.commandString == "Some string")
        #expect(duplicate !== command)

        command.commandString = "Another string"
        #expect(duplicate.commandString == "Some string")
    }

    @Test("A marker no subclass knows gives no command")
    func unknownMarkerGivesNothing() {
        let command: LDrawMetaCommand? = perform("metaCommandInstanceByMarker:scanner:", on: LDrawMetaCommand.self,
                                                 with: "string", Scanner(string: ""))

        #expect(command == nil)
    }
}
