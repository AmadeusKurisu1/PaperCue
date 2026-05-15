//
//  TextWrapping.swift
//  PaperCue
//
//  Created by Codex on 2026/5/12.
//

import Foundation

extension String {
    func paperCueBreakableText(maxRunLength: Int = 18) -> String {
        guard maxRunLength > 0 else { return self }

        var result = ""
        var currentRunLength = 0

        for character in self {
            if character.isWhitespace {
                currentRunLength = 0
                result.append(character)
                continue
            }

            if currentRunLength >= maxRunLength {
                result.append("\u{200B}")
                currentRunLength = 0
            }

            result.append(character)
            currentRunLength += 1
        }

        return result
    }
}
