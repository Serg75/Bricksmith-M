//
//  LibraryUpdateFixtures.swift
//  LDrawLibraryUpdateTests
//
//  Zip archives, release lists and LDraw folders made for the tests.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//

import CryptoKit
import Foundation
import zlib

enum LibraryUpdateFixtures {

    static let listURL = "https://library.ldraw.org/ptreleases/tab"

    /// A new, empty folder in the temporary directory.
    static func temporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LDrawLibraryUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A folder with the files given, each at its path inside the folder.
    static func folder(with files: [String: String]) throws -> URL {
        let folder = temporaryFolder()
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return folder
    }

    /// A small LDraw folder that holds update 2026-10.
    static func library() throws -> URL {
        try folder(with: [
            "parts/3001.dat": "old 3001",
            "parts/3002.dat": "same 3002",
            "parts/s/3001s01.dat": "old subpart",
            "p/stud.dat": "old stud",
            "LDConfig.ldr": "old colors",
            "models/Note2609CA.txt": "notes 2026-09",
            "models/Note2610CA.txt": "notes 2026-10",
            "Unofficial/parts/custom.dat": "mine",
        ])
    }

    static func text(at path: String, in folder: URL) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A row of the release list for an archive.
    static func row(_ kind: String, _ identifier: String, _ archive: Data, format: String = "ZIP",
                    url: String? = nil) -> String {
        let address = url ?? archiveURL(kind, identifier)
        return [kind, identifier, "2026-11-01", format, address, String(archive.count), md5(archive)]
            .joined(separator: "\t")
    }

    /// Where the list says an archive is.
    static func archiveURL(_ kind: String, _ identifier: String) -> String {
        kind == "COMPLETE"
            ? "https://library.ldraw.org/library/updates/complete.zip"
            : "https://library.ldraw.org/library/updates/lcad\(identifier).zip"
    }
}

/// Writes zip archives in memory.
struct ZipWriter {

    /// Deflates the files. Otherwise they are stored as they are.
    var deflates = true

    /// Writes the zip64 records, and each entry's place in a zip64 field.
    var zip64 = false

    func archive(_ files: [(path: String, text: String)]) throws -> Data {
        var archive = Data()
        var directory = Data()

        for file in files {
            let name = Data(file.path.utf8)
            let data = Data(file.text.utf8)
            let deflated = deflates && !data.isEmpty
            let packed = deflated ? try (data as NSData).compressed(using: .zlib) as Data : data
            let method: UInt16 = deflated ? 8 : 0
            let offset = archive.count
            let crc = data.withUnsafeBytes { bytes in
                UInt32(truncatingIfNeeded: crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(bytes.count)))
            }

            // The entry's own header, then its bytes.
            archive.append(number: UInt32(0x04034b50))
            archive.append(number: UInt16(20))
            archive.append(number: UInt16(0x0800))
            archive.append(number: method)
            archive.append(number: UInt32(0))
            archive.append(number: crc)
            archive.append(number: UInt32(packed.count))
            archive.append(number: UInt32(data.count))
            archive.append(number: UInt16(name.count))
            archive.append(number: UInt16(0))
            archive.append(name)
            archive.append(packed)

            // Its record in the directory.
            directory.append(number: UInt32(0x02014b50))
            directory.append(number: UInt16(20))
            directory.append(number: UInt16(20))
            directory.append(number: UInt16(0x0800))
            directory.append(number: method)
            directory.append(number: UInt32(0))
            directory.append(number: crc)
            directory.append(number: UInt32(packed.count))
            directory.append(number: UInt32(data.count))
            directory.append(number: UInt16(name.count))
            directory.append(number: UInt16(zip64 ? 12 : 0))
            directory.append(number: UInt16(0))
            directory.append(number: UInt16(0))
            directory.append(number: UInt16(0))
            directory.append(number: UInt32(0))
            directory.append(number: zip64 ? UInt32.max : UInt32(offset))
            directory.append(name)
            if zip64 {
                directory.append(number: UInt16(1))
                directory.append(number: UInt16(8))
                directory.append(number: UInt64(offset))
            }
        }

        let directoryOffset = archive.count
        archive.append(directory)

        if zip64 {
            let recordOffset = archive.count
            archive.append(number: UInt32(0x06064b50))
            archive.append(number: UInt64(44))
            archive.append(number: UInt16(45))
            archive.append(number: UInt16(45))
            archive.append(number: UInt32(0))
            archive.append(number: UInt32(0))
            archive.append(number: UInt64(files.count))
            archive.append(number: UInt64(files.count))
            archive.append(number: UInt64(directory.count))
            archive.append(number: UInt64(directoryOffset))

            archive.append(number: UInt32(0x07064b50))
            archive.append(number: UInt32(0))
            archive.append(number: UInt64(recordOffset))
            archive.append(number: UInt32(1))
        }

        archive.append(number: UInt32(0x06054b50))
        archive.append(number: UInt16(0))
        archive.append(number: UInt16(0))
        archive.append(number: zip64 ? UInt16.max : UInt16(files.count))
        archive.append(number: zip64 ? UInt16.max : UInt16(files.count))
        archive.append(number: zip64 ? UInt32.max : UInt32(directory.count))
        archive.append(number: zip64 ? UInt32.max : UInt32(directoryOffset))
        archive.append(number: UInt16(0))
        return archive
    }
}

private extension Data {

    /// Appends the number's bytes, lowest first, as zip archives hold them.
    mutating func append<Number: FixedWidthInteger>(number: Number) {
        Swift.withUnsafeBytes(of: number.littleEndian) { append(contentsOf: $0) }
    }
}
