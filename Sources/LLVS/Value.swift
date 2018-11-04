//
//  JSON.swift
//  llvs
//
//  Created by Drew McCormack on 31/10/2018.
//

import Foundation

public struct Value: Codable {
    
    public struct Identifier: StringIdentifiable, Codable {
        public var identifierString: String = UUID().uuidString
    }
    
    var identifier: Identifier
    var version: Version?
    var properties: [String:String] = [:]
}