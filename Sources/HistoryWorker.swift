import AppKit
import ImageIO

final class WorkTicket {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

struct FilePreview {
    let url: URL
    let exists: Bool
}

final class PreparedPreview {
    let text: String
    let characterCount: Int
    let image: CGImage?
    let files: [FilePreview]
    var cost: Int { text.utf8.count + (image.map { $0.bytesPerRow * $0.height } ?? 0) }
    init(text: String, image: CGImage? = nil, files: [FilePreview] = []) {
        self.text = text; self.characterCount = text.count; self.image = image; self.files = files
    }
}

final class PreparedCopy {
    let text: String
    let parts: [PastePart]
    var cost: Int { text.utf8.count + parts.reduce(0) { $0 + $1.representations.values.reduce(0) { $0 + $1.count } } }
    init(text: String, parts: [PastePart]) { self.text = text; self.parts = parts }
}

// One ordered queue owns SQLite and the caches. No disk I/O, JSON decoding,
// image decoding or history search is allowed to block the main thread.
final class HistoryWorker {
    private let queue = DispatchQueue(label: "fr.isaac.recolle.history",qos: .userInitiated)
    private let url: URL
    private var database: HistoryDatabase?
    private let previews = NSCache<NSString,PreparedPreview>()
    private let copies = NSCache<NSString,PreparedCopy>()
    init(url: URL) {
        self.url = url
        previews.totalCostLimit = 48 * 1_024 * 1_024; previews.countLimit = 24
        copies.totalCostLimit = 16 * 1_024 * 1_024; copies.countLimit = 12
    }
    func perform<T>(_ operation: @escaping (HistoryDatabase) throws -> T, completion: @escaping @MainActor (Result<T,Error>) -> Void) {
        queue.async {
            let result: Result<T,Error> = autoreleasepool {
                Result {
                    if self.database == nil { self.database = try HistoryDatabase(url: self.url) }
                    return try operation(self.database!)
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func snapshot(query: String, filter: LibraryFilter, ticket: WorkTicket, completion: @escaping @MainActor (Result<LibrarySnapshot?,Error>) -> Void) {
        perform({ db in
            guard !ticket.cancelled else { return nil }
            let snapshot = try db.snapshot(query: query,filter: filter)
            return ticket.cancelled ? nil : snapshot
        },completion: completion)
    }
    func mutate(query: String, filter: LibraryFilter, invalidateContent: Bool = true, operation: @escaping (HistoryDatabase) throws -> Void, completion: @escaping @MainActor (Result<LibrarySnapshot,Error>) -> Void) {
        perform({ db in
            try operation(db)
            if invalidateContent { self.previews.removeAllObjects(); self.copies.removeAllObjects() }
            return try db.snapshot(query: query,filter: filter)
        },completion: completion)
    }
    private func content(_ id: String, db: HistoryDatabase) throws -> PreparedCopy {
        if let cached = copies.object(forKey: id as NSString) { return cached }
        let value = try db.content(id)
        let copy = PreparedCopy(text: value.text,parts: value.parts)
        if copy.cost <= 16 * 1_024 * 1_024 { copies.setObject(copy,forKey: id as NSString,cost: copy.cost) }
        return copy
    }
    func cachedPreview(id: String, kind: ClipKind) -> PreparedPreview? {
        kind == .files ? nil : previews.object(forKey: id as NSString)
    }
    func preview(id: String, kind: ClipKind, completion: @escaping @MainActor (Result<PreparedPreview,Error>) -> Void) {
        perform({ db in
            if kind != .files, let cached = self.previews.object(forKey: id as NSString) { return cached }
            let text: String
            var image: CGImage?
            if kind == .image {
                let content = try self.content(id,db: db); text = content.text
                for part in content.parts {
                    for type in [NSPasteboard.PasteboardType.png.rawValue,NSPasteboard.PasteboardType.tiff.rawValue,"public.jpeg"] {
                        if let data = part.representations[type], let source = CGImageSourceCreateWithData(data as CFData,nil),
                           let decoded = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                            image = decoded; break
                        }
                    }
                    if image != nil { break }
                }
            } else { text = try db.text(id) }
            let files = kind == .files ? text.split(separator: "\n").compactMap { URL(string: String($0)) }.map { FilePreview(url: $0,exists: FileManager.default.fileExists(atPath: $0.path)) } : []
            let preview = PreparedPreview(text: text,image: image,files: files)
            if kind != .files, preview.cost <= 48 * 1_024 * 1_024 { self.previews.setObject(preview,forKey: id as NSString,cost: preview.cost) }
            return preview
        },completion: completion)
    }
    func copy(id: String?, query: String, filter: LibraryFilter, completion: @escaping @MainActor (Result<(id: String,content: PreparedCopy)?,Error>) -> Void) {
        perform({ db in
            guard let selectedID = try id ?? db.records(query: query,filter: filter).first?.id else { return nil }
            return (selectedID,try self.content(selectedID,db: db))
        },completion: completion)
    }
}
