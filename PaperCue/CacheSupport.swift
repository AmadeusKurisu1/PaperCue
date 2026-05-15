//
//  CacheSupport.swift
//  PaperCue
//
//  Created by Codex on 2026/5/12.
//

import Foundation

enum StableCacheKey {
    static func key(for parts: [String]) -> String {
        let joined = parts.joined(separator: "\u{1F}")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

struct JSONFileCache<Value: Codable> {
    var directory: URL
    var fileManager: FileManager = .default

    func value(forKey key: String) -> Value? {
        let url = directory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func store(_ value: Value, forKey key: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(key).appendingPathExtension("json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
