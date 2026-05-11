//
//  Item.swift
//  PaperCue
//
//  Created by 孙昊 on 2026/5/11.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
