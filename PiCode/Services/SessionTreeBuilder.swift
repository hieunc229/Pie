//
//  SessionTreeBuilder.swift
//  PiCode
//
//  Builds a safe session forest from append-only entries. Corrupt histories may
//  contain duplicate ids or parent cycles, so construction is iterative and
//  breaks one parent edge per cycle before materializing value-type nodes.
//

import Foundation

enum SessionTreeBuilder {
    static func build(from entries: [PiSessionEntry]) -> [PiTreeNode] {
        var entriesByID: [String: PiSessionEntry] = [:]
        var order: [String] = []
        for entry in entries where entriesByID[entry.id] == nil {
            entriesByID[entry.id] = entry
            order.append(entry.id)
        }

        var parentByID: [String: String] = [:]
        for id in order {
            guard let parentID = entriesByID[id]?.parentId,
                  parentID != id,
                  entriesByID[parentID] != nil else { continue }
            parentByID[id] = parentID
        }
        breakParentCycles(in: &parentByID, order: order)

        var childrenByParent: [String: [String]] = [:]
        var roots: [String] = []
        for id in order {
            if let parentID = parentByID[id] {
                childrenByParent[parentID, default: []].append(id)
            } else {
                roots.append(id)
            }
        }

        var labels: [String: (text: String, timestamp: Date?)] = [:]
        for entry in entries where entry.type == "label" {
            if let targetID = entry.targetId, let text = entry.label {
                labels[targetID] = (text, entry.timestamp)
            }
        }

        var nodesByID: [String: PiTreeNode] = [:]
        for rootID in roots {
            var stack: [(id: String, expanded: Bool)] = [(rootID, false)]
            while let frame = stack.popLast() {
                if frame.expanded {
                    guard let entry = entriesByID[frame.id] else { continue }
                    let label = labels[frame.id]
                    let children = (childrenByParent[frame.id] ?? []).compactMap { nodesByID[$0] }
                    nodesByID[frame.id] = PiTreeNode(
                        entry: entry,
                        children: children,
                        label: label?.text,
                        labelTimestamp: label?.timestamp
                    )
                } else {
                    stack.append((frame.id, true))
                    for childID in (childrenByParent[frame.id] ?? []).reversed() {
                        stack.append((childID, false))
                    }
                }
            }
        }
        return roots.compactMap { nodesByID[$0] }
    }

    private static func breakParentCycles(in parentByID: inout [String: String], order: [String]) {
        var resolved = Set<String>()
        for startID in order where !resolved.contains(startID) {
            var path: [String] = []
            var positionByID: [String: Int] = [:]
            var currentID: String? = startID
            while let id = currentID, !resolved.contains(id) {
                if positionByID[id] != nil {
                    parentByID.removeValue(forKey: id)
                    break
                }
                positionByID[id] = path.count
                path.append(id)
                currentID = parentByID[id]
            }
            resolved.formUnion(path)
        }
    }
}
