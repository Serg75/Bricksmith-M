//
//  LPubCommandTests.swift
//  LDrawCoreTests
//
//  How an !LPUB line is parsed, archived and copied, and which subclass it
//  becomes.
//
//  Created by Sergey Slobodenyuk on 2023-03-04.
//

import Testing
import Foundation
import LDrawCore

@Suite("LPub commands")
struct LPubCommandTests {

    @Test("Every LPub meta class is found at run time")
    func subclassesAreFound() throws {
        let names: [String] = try #require(perform("subclassNames", on: LPubCommand.self))

        #expect(Set(names) == ["LPubRemoveGroup",
                               "LPubPliConstrain",
                               "LPubPliShow",
                               "LPubPliIgnore",
                               "LPubPliSubstitute",
                               "LPubPliCameraAngles",
                               "LPubPliPartRotation",
                               "LPubModelScale",
                               "LPubResolution",
                               "LPubPageSize",
                               "LPubPageOrientation"])
    }

    @Test("The LPub text and the whole line are archived, and they read back")
    func archiveRoundTrip() throws {
        let encoder = MockArchiver()
        let command = LPubCommand()
        command.lPubCommandString = "Some string"

        command.encode(with: encoder)

        #expect(encoder.data.count == 2)
        #expect(encoder.data["lpubCommandString"] as? String == "Some string")
        #expect(encoder.data["commandString"] as? String == "!LPUB Some string")

        let decoded = try #require(LPubCommand(coder: encoder))
        #expect(decoded.lPubCommandString == "Some string")
        #expect(decoded.commandString == "!LPUB Some string")
    }

    @Test("A copy has the same text and is a separate object")
    func copyIsSeparate() throws {
        let command = LPubCommand()
        command.lPubCommandString = "Some string"

        let duplicate = try #require(command.copy() as? LPubCommand)
        #expect(duplicate.lPubCommandString == "Some string")
        #expect(duplicate.commandString == command.commandString)
        #expect(duplicate !== command)

        command.lPubCommandString = "Another string"
        #expect(duplicate.lPubCommandString == "Some string")
        #expect(duplicate.commandString != command.commandString)
    }

    @Test("A marker other than !LPUB gives no command")
    func otherMarkerGivesNothing() {
        let command: LDrawMetaCommand? = perform("metaCommandInstanceByMarker:scanner:", on: LPubCommand.self,
                                                 with: "abc", Scanner(string: ""))

        #expect(command == nil)
    }

    @Test("!LPUB makes the subclass its words name, or a plain LPub command", arguments: [
        ("string1 string2", LPubCommand.self),
        ("REMOVE GROUP \"name\"", LPubRemoveGroup.self),
    ] as [(String, AnyClass)])
    func lpubMarkerMakesItsClass(rest: String, expected: AnyClass) throws {
        let command: LDrawMetaCommand = try #require(perform("metaCommandInstanceByMarker:scanner:",
                                                             on: LPubCommand.self,
                                                             with: "!LPUB", Scanner(string: rest)))

        #expect(ObjectIdentifier(type(of: command)) == ObjectIdentifier(expected))
    }

    @Test("A plain LPub command claims no words of its own")
    func plainCommandParsesNothing() {
        let command: LPubCommand? = perform("lpubCommandInstance:", on: LPubCommand.self, with: ["param1", "param2"])

        #expect(command == nil)
    }

    @Test("Finishing a parse keeps the rest of the line from the scanner's place")
    func finishParsingKeepsTheRest() {
        let text = "str1 str2 str3"
        let scanner = Scanner(string: text)
        scanner.currentIndex = text.index(text.startIndex, offsetBy: 5)
        let command = LPubCommand()

        command.finishParsing(scanner)

        #expect(command.lPubCommandString == "str2 str3")
    }

    @Test("The command text is copied, not shared")
    func textIsCopied() {
        let original = NSMutableString(string: "Some string")
        let command = LPubCommand()
        command.lPubCommandString = original as String

        original.append("2")

        #expect(command.lPubCommandString == "Some string")
    }
}
