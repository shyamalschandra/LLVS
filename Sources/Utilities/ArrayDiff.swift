//
//  ArrayMerge.swift
//  LLVS
//
//  Created by Drew McCormack on 02/04/2019.
//

import Foundation

public extension Array where Element: Equatable {
    
    func diff(leadingTo newArray: [Element]) -> ArrayDiff<Element> {
        return ArrayDiff<Element>(originalValues: self, finalValues: newArray)
    }
    
    func applying(_ arrayDiff: ArrayDiff<Element>) -> [Element] {
        var new = self
        new.apply(arrayDiff)
        return new
    }
    
    mutating func apply(_ arrayDiff: ArrayDiff<Element>) {
        for diff in arrayDiff.incrementalChanges {
            apply(diff)
        }
    }
    
    mutating func apply(_ diff: ArrayDiff<Element>.IncrementalChange) {
        switch diff {
        case let .delete(index, _):
            guard indices ~= index else { return }
            remove(at: index)
        case let .insert(index, value):
            let insertIndex = Swift.min(index, count)
            insert(value, at: insertIndex)
        }
    }
    
}

/// See https://en.wikipedia.org/wiki/Longest_common_subsequence_problem
public final class ArrayDiff<T: Equatable> {
    
    /// IncrementalChange indicates a change to the original array.
    /// Indexes of deletions are relative to the original indexes of the original array.
    /// Indexes of insertions are relative to the final array.
    public enum IncrementalChange: Equatable {
        case insert(finalIndex: Int, value: T)
        case delete(originalIndex: Int, value: T)
    }
    
    public let originalValues: [T]
    public let finalValues: [T]
    
    public private(set) var originalIndexesOfCommonElements: [Int] = []
    public private(set) var finalIndexesOfCommonElements: [Int] = []
    
    /// Changes are ordered so that you can apply them in order to the original array,
    /// and end up with the final array. Deletions come first, indexes according to the
    /// original array. They are in reversed order, applying to the end first.
    /// The insertions are next, with the indexes corresponding to the final array.
    /// They apply from the beginning toward the end, ie, standard order.
    public private(set) var incrementalChanges: [IncrementalChange] = []
    
    public var length: Int {
        guard !originalValues.isEmpty, !finalValues.isEmpty else { return 0 }
        return table[(originalValues.count-1, finalValues.count-1)].length
    }
    
    private let table: Table
    
    public init(originalValues: [T], finalValues: [T]) {
        self.originalValues = originalValues
        self.finalValues = finalValues
        self.table = Table(originalLength: self.originalValues.count, newLength: self.finalValues.count)
        fillTable()
        findLongestSubsequence()
    }
    
    private func coordinate(to neighbor: Table.Neighbor, of coordinate: Table.Coordinate) -> Table.Coordinate {
        return neighbor.coordinate(from: coordinate)
    }
    
    private func fillTable() {
        for row in 0..<originalValues.count {
            for col in 0..<finalValues.count {
                let coord = (row, col)
                let left = table[coordinate(to: .left, of: coord)]
                let top = table[coordinate(to: .top, of: coord)]
                var subsequence = table[coord]
                if originalValues[row] == finalValues[col] {
                    let topLeft = table[coordinate(to: .topLeft, of: coord)]
                    subsequence.contributors = [.topLeft]
                    subsequence.length = topLeft.length+1
                } else if left.length > top.length {
                    subsequence.contributors = [.left]
                    subsequence.length = left.length
                } else if top.length > left.length {
                    subsequence.contributors = [.top]
                    subsequence.length = top.length
                } else {
                    subsequence.contributors = [.top, .left]
                    subsequence.length = top.length
                }
                table[coord] = subsequence
            }
        }
    }
    
    private func findLongestSubsequence() {        
        // Begin at end and walk back to origin
        var deletions: [IncrementalChange] = []
        var insertions: [IncrementalChange] = []
        var coord = (originalValues.count-1, finalValues.count-1)
        while coord.0 > -1 || coord.1 > -1 {
            let sub = table[coord]
            
            // Determine the preferred neighbor.
            // Update coord to that neighbor when finished this iteration.
            var preferred: Table.Neighbor?
            defer { coord = preferred!.coordinate(from: coord) }
            
            // Try to move diagonally to top-left
            preferred = sub.contributors.first { neighbor in
                let neighborSub = table[neighbor.coordinate(from: coord)]
                return neighborSub.length < sub.length
            }
            guard preferred == nil else {
                originalIndexesOfCommonElements.insert(coord.0, at: 0)
                finalIndexesOfCommonElements.insert(coord.1, at: 0)
                continue
            }
            
            // Otherwise pick first option
            preferred = sub.contributors.first
            switch preferred! {
            case .left:
                if coord.1 == -1 { break }
                let delta: IncrementalChange = .insert(finalIndex: coord.1, value: finalValues[coord.1])
                insertions.insert(delta, at: 0)
            case .top:
                if coord.0 == -1 { break }
                let delta: IncrementalChange = .delete(originalIndex: coord.0, value: originalValues[coord.0])
                deletions.insert(delta, at: 0)
            case .topLeft:
                fatalError()
            }
        }
        
        // Order changes so that deletions come before insertions, and deletions begin at
        // the end of the array. In this way, you can apply
        // the changes in order to transform from the original to the final array, and not
        // have to be concerned with indexes.
        incrementalChanges = deletions.reversed() + insertions
    }
}

fileprivate extension ArrayDiff {
    
    /// Memoization table
    final class Table: CustomDebugStringConvertible {
        
        typealias Coordinate = (original: Int, new: Int)
        
        enum Neighbor: String, CustomDebugStringConvertible {
            case left
            case top
            case topLeft
            
            var offset: Coordinate {
                switch self {
                case .left:
                    return (0,-1)
                case .top:
                    return (-1,0)
                case .topLeft:
                    return (-1,-1)
                }
            }
            
            func coordinate(from index: Coordinate) -> Coordinate {
                let offset = self.offset
                return (original: index.original + offset.original, new: index.new + offset.new)
            }
            
            var debugDescription: String {
                return self.rawValue
            }
        }
        
        struct Subsequence {
            typealias Length = Int
            var length: Length = 0
            var contributors: [Neighbor] = []
        }
        
        let originalLength: Int
        let newLength: Int
        private var subsequences: [Subsequence]
        
        init(originalLength: Int, newLength: Int) {
            self.originalLength = originalLength
            self.newLength = newLength
            self.subsequences = .init(repeating: Subsequence(), count: (originalLength+1) * (newLength+1))
            for row in 0..<originalLength {
                self[(row,-1)] = Subsequence(length: 0, contributors: [.top])
            }
            for col in 0..<newLength {
                self[(-1,col)] = Subsequence(length: 0, contributors: [.left])
            }
        }
        
        /// Coordinates correspond to the indexes in the original and new arrays.
        /// The storage elements themselves begin at -1, but that is an internal detail.
        subscript(coordinates: (original: Int, new: Int)) -> Subsequence {
            get {
                let i = (coordinates.original+1) * (newLength+1) + (coordinates.new+1)
                return subsequences[i]
            }
            set(newValue) {
                let i = (coordinates.original+1) * (newLength+1) + (coordinates.new+1)
                subsequences[i] = newValue
            }
        }
        
        var debugDescription: String {
            var result = ""
            for row in -1..<originalLength {
                var str = "\n"
                for col in -1..<newLength {
                    let sub = self[(row,col)]
                    str += "(\(sub.length), \(sub.contributors))".padding(toLength: 18, withPad: " ", startingAt: 0)
                }
                result += str
            }
            return result
        }
    }
}
