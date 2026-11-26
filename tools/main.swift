// Refuses a lists.json that breaks the append-only rules, compared with the one people's phones already have.
// Usage: check <published lists.json or "none"> <new lists.json>
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: check <published lists.json or none> <new lists.json>")
    exit(2)
}

func load(_ path: String) -> ListsFile {
    do {
        return try ListsFile.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        print("Can't read \(path): \(error)")
        exit(1)
    }
}

let published = arguments[1] == "none" ? ListsFile(version: ListsFile.supportedVersion, sections: [], lists: []) : load(arguments[1])
let new = load(arguments[2])
var problems = ListsFile.violations(from: published, to: new)
if new.lists.contains(where: { $0.books.isEmpty }) { problems.append("A list has no books") }
if Set(new.lists.map(\.id)).count != new.lists.count { problems.append("Two lists share an ID") }

if problems.isEmpty {
    print("lists.json is fine: \(new.lists.count) lists, \(new.lists.count - published.lists.count) new")
} else {
    print("lists.json can't be published:")
    for problem in problems { print("  - \(problem)") }
    print("Lists are append-only. Removing or changing one needs an app update first.")
    exit(1)
}
