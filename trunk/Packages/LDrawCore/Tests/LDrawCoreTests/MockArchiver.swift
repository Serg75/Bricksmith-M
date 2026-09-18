//
//  MockArchiver.swift
//  LDrawCoreTests
//
//  A coder that keeps what it is given in a dictionary, so a test can see
//  exactly which keys a class writes.
//
//  Created by Sergey Slobodenyuk on 2023-03-06.
//

import Foundation

final class MockArchiver: NSCoder {

    var data: [String: Any] = [:]

    override func encode(_ object: Any?, forKey key: String) {
        data[key] = object
    }

    override func encodeConditionalObject(_ object: Any?, forKey key: String) {
        // Not kept: a conditional object is written only if something else writes it.
    }

    override func decodeObject(forKey key: String) -> Any? {
        data[key]
    }
}

/// Calls a class method the parser uses but no header declares.
func perform<T>(_ selector: String, on type: AnyClass, with arguments: Any...) -> T? {
    let selector = NSSelectorFromString(selector)
    let result: Unmanaged<AnyObject>?

    switch arguments.count {
    case 0: result = (type as AnyObject).perform(selector)
    case 1: result = (type as AnyObject).perform(selector, with: arguments[0])
    default: result = (type as AnyObject).perform(selector, with: arguments[0], with: arguments[1])
    }
    return result?.takeUnretainedValue() as? T
}
