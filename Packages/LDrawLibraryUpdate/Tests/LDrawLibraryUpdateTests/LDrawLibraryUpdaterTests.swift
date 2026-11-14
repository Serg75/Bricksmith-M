//
//  LDrawLibraryUpdaterTests.swift
//  LDrawLibraryUpdateTests
//
//  Tests for updating an LDraw folder, against a stub protocol. No test
//  reaches the network.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//

import Testing
import Foundation
import LDrawLibraryUpdate
import LDrawTestSupport

/// The stub protocol's answers are process-wide, so these run one at a time.
@Suite("Updating a folder, stubbed", .serialized)
struct LDrawLibraryUpdaterTests {

    private typealias Fixtures = LibraryUpdateFixtures

    private let queue = DispatchQueue(label: "LDrawLibraryUpdaterTests")

    /// What update 2026-11 holds: a changed part, an unchanged one, new files,
    /// and entries that must not be installed.
    private let updateFiles: [(path: String, text: String)] = [
        ("ldraw/", ""),
        ("ldraw/parts/", ""),
        ("ldraw/parts/3001.dat", "new 3001"),
        ("ldraw/parts/3002.dat", "same 3002"),
        ("ldraw/parts/99999.DAT", "new part"),
        ("ldraw/parts/s/99999s01.dat", "new subpart"),
        ("ldraw/p/newprim.dat", "new primitive"),
        ("ldraw/LDConfig.ldr", "new colors"),
        ("ldraw/models/Note2611CA.txt", "notes 2026-11"),
        ("ldraw/Unofficial/parts/custom.dat", "theirs"),
        ("other/readme.txt", "outside"),
        ("ldraw/../evil1.txt", "escaped"),
        ("../evil2.txt", "escaped"),
        ("/evil3.txt", "escaped"),
        ("ldraw/parts/../../evil4.txt", "escaped"),
        ("ldraw\\..\\evil5.txt", "escaped"),
        ("ldraw/parts/._3001.dat", "hidden"),
        ("ldraw/.DS_Store", "hidden"),
    ]

    private func updater(for folder: URL) -> LDrawLibraryUpdater {
        let updater = LDrawLibraryUpdater(folderURL: folder)
        updater.sessionConfiguration = StubURLProtocol.configuration()
        return updater
    }

    /// Serves the list and the archives it names.
    private func serve(_ rows: [String], archives: [String: Data]) {
        let list = Data(rows.joined(separator: "\n").utf8)
        StubURLProtocol.answer { request in
            let address = request.url!.absoluteString
            if address == Fixtures.listURL { return .init(status: 200, body: list) }
            guard let body = archives[address] else { return .init(status: 404) }
            return .init(status: 200, body: body)
        }
    }

    private func fetchList(_ updater: LDrawLibraryUpdater) async -> (LDrawLibraryReleaseList?, Error?) {
        await withCheckedContinuation { continuation in
            updater.fetchReleaseList(completionQueue: queue) { list, error in
                continuation.resume(returning: (list, error))
            }
        }
    }

    private func install(_ releases: [LDrawLibraryRelease],
                         with updater: LDrawLibraryUpdater) async -> ([String], Error?) {
        await withCheckedContinuation { continuation in
            _ = updater.install(releases, completionQueue: queue) { added, error in
                continuation.resume(returning: (added, error))
            }
        }
    }

    /// Serves update 2026-11 from the archive, and installs what the list says the folder needs.
    private func installUpdate(_ archive: Data, into folder: URL,
                               listed: Data? = nil) async throws -> ([String], Error?) {
        let complete = try ZipWriter().archive([("ldraw/parts/3001.dat", "complete 3001")])
        serve([Fixtures.row("UPDATE", "2026-10", Data()),
               Fixtures.row("UPDATE", "2026-11", listed ?? archive),
               Fixtures.row("COMPLETE", "2026-11", complete + Data(count: 100_000))],
              archives: [Fixtures.archiveURL("UPDATE", "2026-11"): archive])

        let updater = updater(for: folder)
        let (list, error) = await fetchList(updater)
        #expect(error == nil)

        let installed = LDrawLibraryUpdater.installedRelease(inFolder: folder)
        let releases = try #require(list).releasesToInstall(after: installed)
        #expect(releases.map(\.identifier) == ["2026-11"])
        return await install(releases, with: updater)
    }

    private func code(_ error: Error?) -> Int? {
        guard let error = error as NSError?, error.domain == LDrawLibraryUpdateErrorDomain else { return nil }
        return error.code
    }

    /// The folder is as `Fixtures.library()` made it, with no staging folder left.
    private func expectUntouched(_ folder: URL) throws {
        #expect(Fixtures.text(at: "parts/3001.dat", in: folder) == "old 3001")
        #expect(Fixtures.text(at: "LDConfig.ldr", in: folder) == "old colors")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("parts/99999.DAT").path) == false)
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: folder) == "2026-10")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() ==
                ["LDConfig.ldr", "Unofficial", "models", "p", "parts"])
    }

    // MARK: - The list

    @Test("The list of releases is fetched and read")
    func fetch() async throws {
        let archive = try ZipWriter().archive([("ldraw/parts/1.dat", "1")])
        serve([Fixtures.row("UPDATE", "2026-10", archive), Fixtures.row("COMPLETE", "2026-10", archive)], archives: [:])

        let (list, error) = await fetchList(updater(for: Fixtures.temporaryFolder()))
        #expect(error == nil)
        #expect(list?.latestIdentifier == "2026-10")
        #expect(list?.updates.first?.md5 == Fixtures.md5(archive))
        #expect(StubURLProtocol.requests.map { $0.url?.absoluteString } == [Fixtures.listURL])
    }

    @Test("A server error or a page that is no list is an error")
    func fetchFails() async throws {
        StubURLProtocol.answer { _ in .init(status: 503) }
        let (list, error) = await fetchList(updater(for: Fixtures.temporaryFolder()))
        #expect(list == nil)
        #expect(code(error) == LDrawLibraryUpdateError.badResponse.rawValue)

        StubURLProtocol.answer { _ in .init(status: 200, body: Data("<html>Maintenance</html>".utf8)) }
        let (page, pageError) = await fetchList(updater(for: Fixtures.temporaryFolder()))
        #expect(page == nil)
        #expect(code(pageError) == LDrawLibraryUpdateError.badResponse.rawValue)
    }

    // MARK: - Installing

    @Test("An update's files go into the folder, and nothing else changes",
          arguments: [ZipWriter(deflates: true), ZipWriter(deflates: false), ZipWriter(zip64: true)])
    func install(writer: ZipWriter) async throws {
        let folder = try Fixtures.library()
        let unchanged = folder.appendingPathComponent("parts/3002.dat")
        let fileNumber = try FileManager.default.attributesOfItem(atPath: unchanged.path)[.systemFileNumber] as? Int

        let (added, error) = try await installUpdate(try writer.archive(updateFiles), into: folder)
        #expect(error == nil)
        #expect(added == ["99999.dat"])

        #expect(Fixtures.text(at: "parts/3001.dat", in: folder) == "new 3001")
        #expect(Fixtures.text(at: "parts/99999.DAT", in: folder) == "new part")
        #expect(Fixtures.text(at: "parts/s/99999s01.dat", in: folder) == "new subpart")
        #expect(Fixtures.text(at: "parts/s/3001s01.dat", in: folder) == "old subpart")
        #expect(Fixtures.text(at: "p/newprim.dat", in: folder) == "new primitive")
        #expect(Fixtures.text(at: "p/stud.dat", in: folder) == "old stud")
        #expect(Fixtures.text(at: "LDConfig.ldr", in: folder) == "new colors")
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: folder) == "2026-11")

        // A file with the same bytes stays the file it was.
        let sameFile = try FileManager.default.attributesOfItem(atPath: unchanged.path)[.systemFileNumber] as? Int
        #expect(sameFile == fileNumber)

        #expect(try FileManager.default.contentsOfDirectory(atPath: unchanged.deletingLastPathComponent().path)
            .sorted() == ["3001.dat", "3002.dat", "99999.DAT", "s"])

        // The user's own parts, and everything outside the folder.
        #expect(Fixtures.text(at: "Unofficial/parts/custom.dat", in: folder) == "mine")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() ==
                ["LDConfig.ldr", "Unofficial", "models", "p", "parts"])
        let parent = try FileManager.default.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path)
        #expect(parent.filter { $0.hasPrefix("evil") || $0 == "other" }.isEmpty)
        #expect(FileManager.default.fileExists(atPath: "/evil3.txt") == false)
    }

    @Test("Archives made by zip and ditto are read")
    func realArchives() async throws {
        let bigPart = String(repeating: "1 16 0 0 0 1 0 0 0 1 0 0 0 1 stud.dat\n", count: 4000)
        let source = try Fixtures.folder(with: [
            "ldraw/parts/3001.dat": bigPart,
            "ldraw/parts/99999.dat": "new part",
            "ldraw/models/Note2611CA.txt": "notes 2026-11",
        ])
        let tools: [(String, [String])] = [
            ("/usr/bin/zip", ["-q", "-r", "update.zip", "ldraw"]),
            ("/usr/bin/ditto", ["-c", "-k", "--keepParent", "ldraw", "update.zip"]),
        ]

        for (tool, arguments) in tools where FileManager.default.isExecutableFile(atPath: tool) {
            let archiveURL = source.appendingPathComponent("update.zip")
            try? FileManager.default.removeItem(at: archiveURL)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.currentDirectoryURL = source
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)

            let folder = try Fixtures.library()
            let (added, error) = try await installUpdate(try Data(contentsOf: archiveURL), into: folder)
            #expect(error == nil, "\(tool)")
            #expect(added == ["99999.dat"], "\(tool)")
            #expect(Fixtures.text(at: "parts/3001.dat", in: folder) == bigPart, "\(tool)")
            #expect(LDrawLibraryUpdater.installedRelease(inFolder: folder) == "2026-11", "\(tool)")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("parts").path)
                .sorted() == ["3001.dat", "3002.dat", "99999.dat", "s"], "\(tool)")
        }
    }

    @Test("Several updates are installed in order, and the last one's file wins")
    func twoUpdates() async throws {
        let first = try ZipWriter().archive([("ldraw/parts/3001.dat", "3001 of 2026-11"),
                                             ("ldraw/parts/11111.dat", "part of 2026-11"),
                                             ("ldraw/models/Note2611CA.txt", "notes")])
        let second = try ZipWriter().archive([("ldraw/parts/3001.dat", "3001 of 2026-12"),
                                              ("ldraw/parts/22222.dat", "part of 2026-12"),
                                              ("ldraw/models/Note2612CA.txt", "notes")])
        serve([Fixtures.row("UPDATE", "2026-11", first),
               Fixtures.row("UPDATE", "2026-12", second),
               Fixtures.row("COMPLETE", "2026-12", Data(count: 100_000))],
              archives: [Fixtures.archiveURL("UPDATE", "2026-11"): first,
                         Fixtures.archiveURL("UPDATE", "2026-12"): second])

        let folder = try Fixtures.library()
        let updater = updater(for: folder)
        let list = try #require(await fetchList(updater).0)
        let releases = list.releasesToInstall(after: "2026-10")
        #expect(releases.map(\.identifier) == ["2026-11", "2026-12"])

        let (added, error) = await install(releases, with: updater)
        #expect(error == nil)
        #expect(added == ["11111.dat", "22222.dat"])
        #expect(Fixtures.text(at: "parts/3001.dat", in: folder) == "3001 of 2026-12")
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: folder) == "2026-12")
    }

    @Test("The complete library is installed into a folder that holds no update")
    func complete() async throws {
        let archive = try ZipWriter().archive([("ldraw/parts/3001.dat", "complete 3001"),
                                               ("ldraw/p/stud.dat", "old stud"),
                                               ("ldraw/models/Note2611CA.txt", "notes")])
        serve([Fixtures.row("UPDATE", "2026-11", Data()), Fixtures.row("COMPLETE", "2026-11", archive)],
              archives: [Fixtures.archiveURL("COMPLETE", "2026-11"): archive])

        let folder = try Fixtures.folder(with: ["p/stud.dat": "old stud", "parts/mine.dat": "kept"])
        let updater = updater(for: folder)
        let list = try #require(await fetchList(updater).0)
        let releases = list.releasesToInstall(after: LDrawLibraryUpdater.installedRelease(inFolder: folder))
        #expect(releases.map(\.isComplete) == [true])

        let (added, error) = await install(releases, with: updater)
        #expect(error == nil)
        #expect(added == ["3001.dat"])
        #expect(Fixtures.text(at: "parts/mine.dat", in: folder) == "kept")
        #expect(LDrawLibraryUpdater.installedRelease(inFolder: folder) == "2026-11")
    }

    // MARK: - Failures

    @Test("A download that is not the listed file is refused, and the folder is left alone")
    func badDownload() async throws {
        let archive = try ZipWriter().archive(updateFiles)
        var changed = archive
        changed[40] ^= 0xff

        // Same size, other bytes.
        let folder = try Fixtures.library()
        let (added, error) = try await installUpdate(changed, into: folder, listed: archive)
        #expect(added.isEmpty)
        #expect(code(error) == LDrawLibraryUpdateError.badDownload.rawValue)
        try expectUntouched(folder)

        // Other size.
        let (_, sizeError) = try await installUpdate(archive + Data(count: 1), into: folder, listed: archive)
        #expect(code(sizeError) == LDrawLibraryUpdateError.badDownload.rawValue)
        try expectUntouched(folder)
    }

    @Test("A missing archive is an error, and the folder is left alone")
    func missingArchive() async throws {
        let archive = try ZipWriter().archive(updateFiles)
        serve([Fixtures.row("UPDATE", "2026-11", archive), Fixtures.row("COMPLETE", "2026-11", Data(count: 100_000))],
              archives: [:])

        let folder = try Fixtures.library()
        let updater = updater(for: folder)
        let list = try #require(await fetchList(updater).0)
        let (added, error) = await install(list.releasesToInstall(after: "2026-10"), with: updater)
        #expect(added.isEmpty)
        #expect(code(error) == LDrawLibraryUpdateError.badResponse.rawValue)
        try expectUntouched(folder)
    }

    @Test("A broken archive is an error, and the folder is left alone")
    func badArchive() async throws {
        let folder = try Fixtures.library()

        // Not a zip archive at all.
        let (_, error) = try await installUpdate(Data("This is not a zip archive.".utf8), into: folder)
        #expect(code(error) == LDrawLibraryUpdateError.badArchive.rawValue)
        try expectUntouched(folder)

        // A file whose bytes do not match its CRC.
        let writer = ZipWriter(deflates: false)
        var archive = try writer.archive(updateFiles)
        let range = try #require(archive.range(of: Data("new 3001".utf8)))
        archive.replaceSubrange(range, with: Data("bad 3001".utf8))
        let (_, crcError) = try await installUpdate(archive, into: folder)
        #expect(code(crcError) == LDrawLibraryUpdateError.badArchive.rawValue)
        try expectUntouched(folder)

        // An archive with nothing under "ldraw/".
        let empty = try ZipWriter().archive([("readme.txt", "nothing")])
        let (_, emptyError) = try await installUpdate(empty, into: folder)
        #expect(code(emptyError) == LDrawLibraryUpdateError.badArchive.rawValue)
        try expectUntouched(folder)
    }

    @Test("When a file cannot be put in place, the files and folders before it are taken back out")
    func rollback() async throws {
        let folder = try Fixtures.library()
        let manager = FileManager.default

        // A folder where the update has a file. It sorts after the other parts.
        let blocked = folder.appendingPathComponent("parts/zzz.dat")
        try manager.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: blocked.appendingPathComponent("kept.txt"))

        // A link that leads nowhere, where the update has a new part.
        let link = folder.appendingPathComponent("parts/99999.DAT")
        try manager.createSymbolicLink(atPath: link.path, withDestinationPath: "nowhere.dat")

        let files = updateFiles + [("ldraw/parts/textures/new/tex.png", "texture"), ("ldraw/parts/zzz.dat", "a file")]
        let (added, error) = try await installUpdate(try ZipWriter().archive(files), into: folder)
        #expect(added.isEmpty)
        #expect(code(error) == LDrawLibraryUpdateError.badArchive.rawValue)

        try expectUntouched(folder)
        #expect(Fixtures.text(at: "parts/zzz.dat/kept.txt", in: folder) == "inside")
        #expect(manager.fileExists(atPath: folder.appendingPathComponent("p/newprim.dat").path) == false)
        #expect(try manager.destinationOfSymbolicLink(atPath: link.path) == "nowhere.dat")
        #expect(try manager.contentsOfDirectory(atPath: folder.appendingPathComponent("parts").path).sorted() ==
                ["3001.dat", "3002.dat", "99999.DAT", "s", "zzz.dat"])
    }

    @Test("A folder another update has locked is an error, and its staging folder stays")
    func busy() async throws {
        let folder = try Fixtures.library()
        let staging = folder.appendingPathComponent(".bricksmith-update-other")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let lock = open(folder.path, O_RDONLY | O_DIRECTORY)
        try #require(lock >= 0)
        defer { close(lock) }
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)

        let (added, error) = try await installUpdate(try ZipWriter().archive(updateFiles), into: folder)
        #expect(added.isEmpty)
        #expect(code(error) == LDrawLibraryUpdateError.busy.rawValue)
        #expect(FileManager.default.fileExists(atPath: staging.path))
        #expect(StubURLProtocol.requests.map { $0.url?.absoluteString } == [Fixtures.listURL])
        #expect(Fixtures.text(at: "parts/3001.dat", in: folder) == "old 3001")
    }

    @Test("A folder that cannot be written is an error before any download")
    func notWritable() async throws {
        let folder = try Fixtures.library()
        let archive = try ZipWriter().archive(updateFiles)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        let (added, error) = try await installUpdate(archive, into: folder)
        #expect(added.isEmpty)
        #expect(code(error) == LDrawLibraryUpdateError.notWritable.rawValue)
        #expect(StubURLProtocol.requests.map { $0.url?.absoluteString } == [Fixtures.listURL])
    }

    @Test("A cancel during the download stops the update, and the folder is left alone")
    func cancel() async throws {
        let archive = try ZipWriter().archive(updateFiles)
        let list = Data([Fixtures.row("UPDATE", "2026-11", archive),
                         Fixtures.row("COMPLETE", "2026-11", Data(count: 100_000))].joined(separator: "\n").utf8)
        let asked = DispatchSemaphore(value: 0)
        let canceled = DispatchSemaphore(value: 0)

        // The archive's answer waits until the update is canceled.
        StubURLProtocol.answer { request in
            if request.url!.absoluteString == Fixtures.listURL { return .init(status: 200, body: list) }
            asked.signal()
            canceled.wait()
            return .init(status: 200, body: archive)
        }

        let folder = try Fixtures.library()
        let updater = updater(for: folder)
        let releases = try #require(await fetchList(updater).0).releasesToInstall(after: "2026-10")

        let (added, error): ([String], Error?) = await withCheckedContinuation { continuation in
            let progress = updater.install(releases, completionQueue: queue) { added, error in
                continuation.resume(returning: (added, error))
            }
            queue.async {
                asked.wait()
                progress.cancel()
                canceled.signal()
            }
        }
        #expect(added.isEmpty)
        #expect(code(error) == LDrawLibraryUpdateError.canceled.rawValue)
        try expectUntouched(folder)
    }
}
