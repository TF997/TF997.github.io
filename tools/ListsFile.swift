// The reading lists' file format and its append-only rules. Pure Foundation, so the website's publishing check can run
// this same file. Keep Website/tools/ListsFile.swift identical to it (a test checks).
import Foundation

/// A book on a reading list.
struct ListedBook: Identifiable, Hashable, Codable {
    let title: String
    let author: String
    /// The usual length, when Open Library knows it.
    var pages: Int?
    /// Open Library's number for a good cover. Without one the cover is drawn.
    var coverID: Int?
    var isWinner = false

    enum CodingKeys: String, CodingKey { case title, author, pages, coverID, isWinner = "winner" }

    init(title: String, author: String, pages: Int? = nil, coverID: Int? = nil, isWinner: Bool = false) {
        (self.title, self.author, self.pages, self.coverID, self.isWinner) = (title, author, pages, coverID, isWinner)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        pages = try c.decodeIfPresent(Int.self, forKey: .pages)
        coverID = try c.decodeIfPresent(Int.self, forKey: .coverID)
        isWinner = try c.decodeIfPresent(Bool.self, forKey: .isWinner) ?? false
    }

    var id: String { "\(title)|\(author)" }

    func coverURL(size: String) -> URL? {
        coverID.flatMap { Self.coverURL(id: $0, size: size) }
    }

    static func coverURL(id: Int, size: String) -> URL? {
        URL(string: "https://covers.openlibrary.org/b/id/\(id)-\(size).jpg?default=false")
    }

    /// Whether this is the same book, allowing for subtitles, a leading "The", accents and punctuation, and for the
    /// author's name being written another way round or with others beside it.
    func matches(title otherTitle: String, author otherAuthor: String) -> Bool {
        guard Self.key(title) == Self.key(otherTitle) else { return false }
        let names = Self.words(author), others = Set(Self.words(otherAuthor))
        // Some books are added with no author.
        return others.isEmpty || names.contains { $0.count > 2 && others.contains($0) }
    }

    private static func key(_ title: String) -> [String] {
        let main = title.components(separatedBy: CharacterSet(charactersIn: ":;(")).first ?? title
        // "A.B.C." and "ABC" are the same.
        let words = words(main.replacingOccurrences(of: ".", with: ""))
        return words.count > 1 && ["the", "a", "an"].contains(words[0]) ? Array(words.dropFirst()) : words
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "['’]", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

/// A list of books to choose from: a prize's, or one put together for Readthroughs.
struct ReadingList: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case prize, author, genre }

    /// Never changes, so earned things and progress stay tied to the list whatever it's called.
    let id: String
    let name: String
    var detail: String?
    let kind: Kind
    let books: [ListedBook]
}

/// Every list, and how they're grouped on the Lists tab. The app ships with one copy (`lists.json`) and fetches newer
/// ones from the website, so new lists arrive without an app update.
///
/// Lists are append-only: once a list is published, its books never change, so nobody's progress through it moves.
/// New lists can be added, and a book's cover or page count corrected. Taking a list away needs an app update.
struct ListsFile: Codable, Equatable {
    /// Files newer than this app understands are ignored.
    static let supportedVersion = 1

    struct Section: Codable, Equatable {
        let title: String
        let lists: [String]
    }

    var version: Int
    var sections: [Section]
    var lists: [ReadingList]

    static func decode(_ data: Data) throws -> ListsFile {
        let file = try JSONDecoder().decode(ListsFile.self, from: data)
        guard file.version <= supportedVersion else { throw CocoaError(.fileReadCorruptFile) }
        return file
    }

    /// `incoming` on top of what's known, keeping the rules: every known list stays, with its books as they were. Only
    /// covers and page counts are taken from `incoming`, and only for the same book in the same place. New lists are
    /// added. The grouping follows `incoming`, and a known list it leaves out goes at the end of the last group.
    static func merged(known: ListsFile, incoming: ListsFile) -> ListsFile {
        let incomingByID = Dictionary(incoming.lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lists = known.lists.map { list -> ReadingList in
            guard let newer = incomingByID[list.id] else { return list }
            let books = list.books.enumerated().map { index, book -> ListedBook in
                guard index < newer.books.count, newer.books[index].title == book.title, newer.books[index].author == book.author else {
                    return book
                }
                return ListedBook(title: book.title, author: book.author, pages: newer.books[index].pages ?? book.pages,
                                  coverID: newer.books[index].coverID ?? book.coverID, isWinner: book.isWinner)
            }
            return ReadingList(id: list.id, name: list.name, detail: list.detail, kind: list.kind, books: books)
        }
        let knownIDs = Set(lists.map(\.id))
        lists += incoming.lists.filter { !knownIDs.contains($0.id) && !$0.books.isEmpty }

        let ids = Set(lists.map(\.id))
        var sections = incoming.sections.map { Section(title: $0.title, lists: $0.lists.filter(ids.contains)) }.filter { !$0.lists.isEmpty }
        if sections.isEmpty { sections = known.sections }
        let shown = Set(sections.flatMap(\.lists))
        let hidden = lists.map(\.id).filter { !shown.contains($0) }
        if !hidden.isEmpty, let last = sections.indices.last {
            sections[last] = Section(title: sections[last].title, lists: sections[last].lists + hidden)
        }
        return ListsFile(version: max(known.version, incoming.version), sections: sections, lists: lists)
    }

    /// What `newer` does that the rules don't allow, compared with `older`. Empty when it's safe to publish.
    static func violations(from older: ListsFile, to newer: ListsFile) -> [String] {
        var problems: [String] = []
        let newerByID = Dictionary(newer.lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if newerByID.count != newer.lists.count { problems.append("Two lists share an ID") }
        for list in older.lists {
            guard let now = newerByID[list.id] else {
                problems.append("\(list.id) was removed")
                continue
            }
            if now.books.map(\.title) != list.books.map(\.title) || now.books.map(\.author) != list.books.map(\.author) {
                problems.append("\(list.id) has different books")
            } else if now.books.map(\.isWinner) != list.books.map(\.isWinner) {
                problems.append("\(list.id) has a different winner")
            }
        }
        let listed = Set(newer.sections.flatMap(\.lists))
        for id in listed where newerByID[id] == nil { problems.append("A group lists \(id), which isn't there") }
        return problems
    }
}
