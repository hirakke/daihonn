//
//  Item.swift
//  daihonn
//
//  Created by Keiju Hiramoto on 2025/08/10.
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
