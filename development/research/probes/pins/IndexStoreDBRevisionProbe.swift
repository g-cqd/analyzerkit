// ADR-0025: the same probe built twice, against indexstore-db `0390867` (main) and `64aa0b2` (release/6.4.x), each in a
// package of its own (`.package(url: "https://github.com/swiftlang/indexstore-db.git", revision: …)`, Swift 5 mode).
// Usage: isprobe <store> <libIndexStore.dylib> <database directory> <names>

import Dispatch
import Foundation
import IndexStoreDB

// Usage: isprobe <store> <libIndexStore.dylib> <db dir> <names>
let args = CommandLine.arguments
let (store, lib, dbPath, nameCount) = (args[1], args[2], args[3], Int(args[4]) ?? 2000)
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

let t0 = now()
let library = try IndexStoreLibrary(dylibPath: lib)
let db = try IndexStoreDB(
    storePath: store, databasePath: dbPath, library: library, waitUntilDoneInitializing: true, listenToUnitEvents: false
)
db.pollForUnitChangesAndWait()
let tImport = now() - t0

var names: [String] = []
db.forEachSymbolName {
    names.append($0); return true
}
names.sort()
let step = max(1, names.count / nameCount)
let picked = stride(from: 0, to: names.count, by: step).map { names[$0] }
let t1 = now()
var occurrences = 0
for name in picked { occurrences += db.canonicalOccurrences(ofName: name).count }
let tByName = now() - t1

// Occurrences of the most referenced USRs: what a reference scan pays.
let t2 = now()
var related = 0
for name in picked.prefix(500) {
    for symbol in db.canonicalOccurrences(ofName: name).prefix(1) {
        related += db.occurrences(ofUSR: symbol.symbol.usr, roles: [.reference, .call]).count
    }
}
let tRefs = now() - t2
print(
    String(
        format: "import %.2f s  names %d  byName(%d) %.3f s -> %d  refs(500) %.3f s -> %d",
        tImport, names.count, picked.count, tByName, occurrences, tRefs, related))

// Heavy: every occurrence of very common symbols, spread over thousands of records.
let t3 = now()
var heavy = 0
var usrs = 0
for name in ["String", "Int", "Bool", "View", "Text", "Array", "Optional", "Date", "UUID", "Error"] {
    for symbol in db.canonicalOccurrences(ofName: name) {
        usrs += 1
        heavy += db.occurrences(ofUSR: symbol.symbol.usr, roles: .all).count
    }
}
print(String(format: "heavy %.3f s -> %d occurrences of %d symbols", now() - t3, heavy, usrs))
