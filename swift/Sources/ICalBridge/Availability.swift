import Foundation

struct BusyInterval: Equatable {
    let start: Date
    let end: Date
    let title: String?
}

struct FreeInterval: Equatable {
    let start: Date
    let end: Date
}

enum Availability {
    static func merge(busy: [BusyInterval], granularityMinutes: Int) -> [BusyInterval] {
        guard !busy.isEmpty else { return [] }
        let gap = TimeInterval(granularityMinutes * 60)
        let sorted = busy.sorted { $0.start < $1.start }
        var out: [BusyInterval] = []
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.start.timeIntervalSince(current.end) < gap {
                let mergedEnd = max(current.end, next.end)
                let mergedTitle = current.title
                current = BusyInterval(start: current.start, end: mergedEnd, title: mergedTitle)
            } else {
                out.append(current)
                current = next
            }
        }
        out.append(current)
        return out
    }

    static func freeBlocks(rangeStart: Date, rangeEnd: Date, merged: [BusyInterval]) -> [FreeInterval] {
        var out: [FreeInterval] = []
        var cursor = rangeStart
        for b in merged {
            let bStart = max(b.start, rangeStart)
            let bEnd = min(b.end, rangeEnd)
            if bStart > cursor {
                out.append(FreeInterval(start: cursor, end: bStart))
            }
            cursor = max(cursor, bEnd)
        }
        if cursor < rangeEnd {
            out.append(FreeInterval(start: cursor, end: rangeEnd))
        }
        return out
    }
}
