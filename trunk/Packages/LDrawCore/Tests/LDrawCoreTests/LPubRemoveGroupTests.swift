//
//  LPubRemoveGroupTests.swift
//  LDrawCoreTests
//
//  How 0 !LPUB REMOVE GROUP is parsed, archived and copied.
//
//  Created by Sergey Slobodenyuk on 2023-03-09.
//

import Testing
import Foundation
import LDrawCore

@Suite("LPub REMOVE GROUP")
struct LPubRemoveGroupTests {

    private func parsed(_ parameters: [String]) -> LPubRemoveGroup? {
        perform("lpubCommandInstance:", on: LPubRemoveGroup.self, with: parameters)
    }

    @Test("The name, the LPub text and the whole line are archived, and they read back")
    func archiveRoundTrip() throws {
        let encoder = MockArchiver()
        let command = LPubRemoveGroup()
        command.groupName = "Some string"

        command.encode(with: encoder)

        #expect(encoder.data.count == 3)
        #expect(encoder.data["groupName"] as? String == "Some string")
        #expect(encoder.data["lpubCommandString"] as? String == "REMOVE GROUP \"Some string\"")
        #expect(encoder.data["commandString"] as? String == "!LPUB REMOVE GROUP \"Some string\"")

        let decoded = try #require(LPubRemoveGroup(coder: encoder))
        #expect(decoded.groupName == "Some string")
        #expect(decoded.lPubCommandString == "REMOVE GROUP \"Some string\"")
        #expect(decoded.commandString == "!LPUB REMOVE GROUP \"Some string\"")
    }

    @Test("A copy has the same name and text and is a separate object")
    func copyIsSeparate() throws {
        let command = LPubRemoveGroup()
        command.groupName = "Some string"

        let duplicate = try #require(command.copy() as? LPubRemoveGroup)
        #expect(duplicate.groupName == "Some string")
        #expect(duplicate.lPubCommandString == command.lPubCommandString)
        #expect(duplicate.commandString == command.commandString)
        #expect(duplicate !== command)

        command.groupName = "Another string"
        #expect(duplicate.groupName == "Some string")
        #expect(duplicate.lPubCommandString != command.lPubCommandString)
        #expect(duplicate.commandString != command.commandString)
    }

    @Test("Anything but REMOVE GROUP and one name is not this command", arguments: [
        ["REMOVE", "GROUP"],
        ["REMOVE", "GROUP", "\"name\"", "extra"],
        ["REMOVE", "GROUPS", "\"name\""],
    ])
    func wrongWordsGiveNothing(parameters: [String]) {
        #expect(parsed(parameters) == nil)
    }

    @Test("REMOVE GROUP and a quoted name makes the command")
    func expectedWordsMakeTheCommand() throws {
        let command = try #require(parsed(["REMOVE", "GROUP", "\"name\""]))

        #expect(ObjectIdentifier(type(of: command)) == ObjectIdentifier(LPubRemoveGroup.self))
        #expect(command.groupName == "name")
        #expect(command.lPubCommandString == "REMOVE GROUP \"name\"")
        #expect(command.commandString == "!LPUB REMOVE GROUP \"name\"")
    }

    /// The name has a space, so a plain split on spaces would lose it.
    @Test("Retyped text is read again, quoted name and all")
    func retypedTextIsReadAgain() throws {
        let command = try #require(parsed(["REMOVE", "GROUP", "\"name\""]))

        command.lPubCommandString = "REMOVE GROUP \"foo bar\""
        #expect(command.groupName == "foo bar")
        #expect(command.lPubCommandString == "REMOVE GROUP \"foo bar\"")

        command.lPubCommandString = "REMOVE GROUP \"wheels\""
        #expect(command.groupName == "wheels")
    }

    @Test("Finishing a parse leaves the name alone")
    func finishParsingChangesNothing() throws {
        let command = try #require(parsed(["REMOVE", "GROUP", "\"name\""]))

        command.finishParsing(Scanner(string: ""))

        #expect(command.groupName == "name")
    }

    @Test("The group name is copied, not shared")
    func nameIsCopied() throws {
        let command = try #require(parsed(["REMOVE", "GROUP", "\"name\""]))
        let original = NSMutableString(string: "group")

        command.groupName = original as String
        original.append("2")

        #expect(command.groupName == "group")
    }
}
