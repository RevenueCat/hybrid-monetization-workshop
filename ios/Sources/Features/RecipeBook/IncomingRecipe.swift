import Foundation

/// Source-neutral envelope. Future capture methods can add a kind and a local asset reference.
struct RecipeSource: Codable, Equatable {
    var kind: String
    var value: String

    static func webURL(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let candidate = URLComponents(string: text)?.scheme == nil ? "https://" + text : text
        guard let url = URL(string: candidate), let source = try? web(url),
              let host = URL(string: source.value)?.host, host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return URL(string: source.value)
    }

    static func web(_ url: URL) throws -> Self {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else {
            throw IncomingRecipeError.invalidSource
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        parts.fragment = nil
        guard let normalized = parts.url else { throw IncomingRecipeError.invalidSource }
        return .init(kind: "web", value: normalized.absoluteString)
    }
    var caption: String { URL(string: value)?.host ?? "New recipe" }
}

struct IncomingRecipe: Codable, Identifiable {
    enum Status: String, Codable { case ready, waiting, preparing, failed, complete }
    var id: String = UUID().uuidString.lowercased()
    var source: RecipeSource
    var title: String
    var createdAt: Date = Date()
    var requestedAt: Date?
    var status: Status = .ready
    /// Stable across uncertain retries so the spending service can make the debit idempotent.
    var spendOperationID: String? = UUID().uuidString.lowercased()
    var preparedRecipe: Data?
    var mockTemplateID: String?
    var recipeID: String { "import-" + id }
    var effectiveSpendOperationID: String { spendOperationID ?? id }
}

struct IncomingRecipeDocument: Codable {
    var version = 1
    var nextMockTemplateIndex = 0
    var items: [IncomingRecipe] = []

    init(version: Int = 1, nextMockTemplateIndex: Int = 0,
         items: [IncomingRecipe] = []) {
        self.version = version
        self.nextMockTemplateIndex = nextMockTemplateIndex
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case version, nextMockTemplateIndex, items
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try values.decodeIfPresent([IncomingRecipe].self, forKey: .items) ?? []
        nextMockTemplateIndex = try values.decodeIfPresent(Int.self, forKey: .nextMockTemplateIndex)
            ?? items.filter { $0.status == .complete }.count % 2
    }
}

enum IncomingRecipeError: LocalizedError {
    case unavailable, invalidSource, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .unavailable: "Kitchen Table’s recipe storage is unavailable. Please try again."
        case .invalidSource: "Enter a valid recipe webpage link."
        case .unsupportedVersion: "These recipes were saved by a newer version of Kitchen Table."
        }
    }
}

/// Coordinate import reads and writes. Failed reads never become empty writes.
final class IncomingRecipeRepository {
    let fileURL: URL

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("incoming-recipes.json")
    }
    private func read(_ url: URL) throws -> IncomingRecipeDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let document = try JSONDecoder().decode(IncomingRecipeDocument.self, from: Data(contentsOf: url))
        guard document.version == 1 else { throw IncomingRecipeError.unsupportedVersion }
        return document
    }
    func load() throws -> IncomingRecipeDocument {
        var coordinationError: NSError?
        var result: Result<IncomingRecipeDocument, Error>?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Result { try read(url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw IncomingRecipeError.unavailable }
        return try result.get()
    }
    @discardableResult
    func update(_ change: (inout IncomingRecipeDocument) throws -> Void) throws -> IncomingRecipeDocument {
        var coordinationError: NSError?
        var result: Result<IncomingRecipeDocument, Error>?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            result = Result {
                var document = try read(url)
                try change(&document)
                try JSONEncoder().encode(document).write(to: url, options: .atomic)
                return document
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw IncomingRecipeError.unavailable }
        return try result.get()
    }
    /// Returns false when this source is already pending. Completed sources can be shared again.
    @discardableResult
    func capture(url: URL, title: String?) throws -> Bool {
        let source = try RecipeSource.web(url)
        var inserted = false
        try update { document in
            guard !document.items.contains(where: { $0.source == source && $0.status != .complete }) else { return }
            let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = cleaned.flatMap { $0.isEmpty || $0 == url.absoluteString ? nil : String($0.prefix(240)) }
            document.items.append(.init(source: source, title: name ?? source.caption))
            inserted = true
        }
        return inserted
    }
}
