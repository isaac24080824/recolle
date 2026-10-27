import Foundation
import SQLite3

private let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class HistoryDatabase {
    private var db: OpaquePointer?
    static let defaultMaxCount = 5_000
    static let defaultMaxBytes = 250 * 1_024 * 1_024
    let maxCount: Int
    let maxBytes: Int

    init(url: URL, maxCount: Int = defaultMaxCount, maxBytes: Int = defaultMaxBytes) throws {
        self.maxCount = maxCount; self.maxBytes = maxBytes
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw RecolleError.database("Ouverture impossible.") }
        do {
            sqlite3_busy_timeout(db, 2_000)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("PRAGMA secure_delete=ON")
            try execute("""
                CREATE TABLE IF NOT EXISTS clips (
                  id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
                  title TEXT NOT NULL, body TEXT NOT NULL, search TEXT NOT NULL,
                  source_name TEXT NOT NULL, source_bundle TEXT NOT NULL,
                  created REAL NOT NULL, last_copied REAL NOT NULL,
                  copy_count INTEGER NOT NULL DEFAULT 1, favorite INTEGER NOT NULL DEFAULT 0,
                  byte_count INTEGER NOT NULL, payload BLOB NOT NULL, list_order REAL
                );
                CREATE INDEX IF NOT EXISTS clips_recent_order ON clips(last_copied DESC,id DESC);
                CREATE INDEX IF NOT EXISTS clips_kind_order ON clips(kind,last_copied DESC,id DESC);
                CREATE INDEX IF NOT EXISTS clips_favorite_order ON clips(last_copied DESC,id DESC) WHERE favorite=1;
                CREATE INDEX IF NOT EXISTS clips_counts ON clips(kind,favorite);
                CREATE INDEX IF NOT EXISTS clips_size ON clips(byte_count);
                """)
            // Display order is separate from last use: quick copies must keep
            // their position while still refreshing retention and copy counts.
            try execute("BEGIN IMMEDIATE")
            do {
                let columns = try prepare("PRAGMA table_info(clips)")
                var hasListOrder = false
                while sqlite3_step(columns) == SQLITE_ROW {
                    if string(columns,1) == "list_order" { hasListOrder = true }
                }
                sqlite3_finalize(columns)
                if !hasListOrder { try execute("ALTER TABLE clips ADD COLUMN list_order REAL") }
                try execute("""
                    UPDATE clips SET list_order=last_copied WHERE list_order IS NULL;
                    CREATE INDEX IF NOT EXISTS clips_display_order ON clips(list_order DESC,id DESC);
                    CREATE INDEX IF NOT EXISTS clips_kind_display_order ON clips(kind,list_order DESC,id DESC);
                    CREATE INDEX IF NOT EXISTS clips_favorite_display_order ON clips(list_order DESC,id DESC) WHERE favorite=1;
                    PRAGMA user_version=2;
                    """)
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    private func error() -> RecolleError { .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Base indisponible.") }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error() }
        return stmt
    }
    private func bind(_ value: String, _ index: Int32, _ stmt: OpaquePointer) {
        value.withCString { _ = sqlite3_bind_text(stmt,index,$0,Int32(value.utf8.count),sqlTransient) }
    }
    private func string(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let p = sqlite3_column_text(stmt, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: p,count: Int(sqlite3_column_bytes(stmt,index))),as: UTF8.self)
    }
    private func done(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    @discardableResult func save(_ capture: Capture, at date: Date = Date()) throws -> String {
        let payload = try capture.encoded
        let fingerprint = capture.fingerprint
        try execute("BEGIN IMMEDIATE")
        do {
            var existing: String?
            let lookup = try prepare("SELECT id FROM clips WHERE fingerprint=?")
            bind(fingerprint, 1, lookup)
            if sqlite3_step(lookup) == SQLITE_ROW { existing = string(lookup, 0) }
            sqlite3_finalize(lookup)
            let id = existing ?? UUID().uuidString
            let stmt = try prepare("""
                INSERT INTO clips (id,fingerprint,kind,title,body,search,source_name,source_bundle,created,last_copied,byte_count,payload,list_order)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(fingerprint) DO UPDATE SET last_copied=excluded.last_copied,list_order=excluded.list_order,
                copy_count=clips.copy_count+1,source_name=excluded.source_name,source_bundle=excluded.source_bundle,
                search=excluded.search,payload=excluded.payload,byte_count=excluded.byte_count
                """)
            defer { sqlite3_finalize(stmt) }
            for (i, value) in [id,fingerprint,capture.kind.rawValue,capture.title,capture.text,(capture.text + " " + capture.title + " " + capture.sourceName).searchKey,capture.sourceName,capture.sourceBundle].enumerated() {
                bind(value, Int32(i + 1), stmt)
            }
            sqlite3_bind_double(stmt, 9, date.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 10, date.timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 11, Int64(payload.count + capture.text.utf8.count * 2))
            payload.withUnsafeBytes { bytes in _ = sqlite3_bind_blob(stmt, 12, bytes.baseAddress, Int32(payload.count), sqlTransient) }
            sqlite3_bind_double(stmt,13,date.timeIntervalSince1970)
            try done(stmt)
            try enforceLimits(protecting: id)
            try execute("COMMIT")
            return id
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func enforceLimits(protecting id: String) throws {
        while true {
            let summary = try prepare("SELECT COUNT(*),COALESCE(SUM(byte_count),0) FROM clips")
            guard sqlite3_step(summary) == SQLITE_ROW else { sqlite3_finalize(summary); throw error() }
            let count = sqlite3_column_int64(summary,0), bytes = sqlite3_column_int64(summary,1)
            sqlite3_finalize(summary)
            if count <= maxCount && bytes <= maxBytes { return }
            let oldest = try prepare("SELECT id FROM clips WHERE favorite=0 AND id!=? ORDER BY last_copied ASC LIMIT 1")
            bind(id, 1, oldest)
            guard sqlite3_step(oldest) == SQLITE_ROW else { sqlite3_finalize(oldest); throw RecolleError.capacity }
            let deleteID = string(oldest,0); sqlite3_finalize(oldest)
            try delete(deleteID, checkpoint: false)
        }
    }

    func records(query: String = "", filter: LibraryFilter = .all) throws -> [ClipRecord] {
        let terms = query.searchKey.split(whereSeparator: \.isWhitespace).map(String.init)
        var conditions: [String] = []
        if filter == .favorites { conditions.append("favorite=1") }
        else if filter != .all { conditions.append("kind='\(filter.rawValue)'") }
        conditions += terms.map { _ in "instr(search,?)>0" }
        let whereSQL = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        let stmt = try prepare("SELECT id,kind,title,substr(body,1,400),source_name,source_bundle,created,last_copied,copy_count,favorite,byte_count FROM clips" + whereSQL + " ORDER BY list_order DESC,id DESC")
        defer { sqlite3_finalize(stmt) }
        for (i, term) in terms.enumerated() { bind(term, Int32(i+1), stmt) }
        var rows: [ClipRecord] = []
        var result = sqlite3_step(stmt)
        while result == SQLITE_ROW {
            rows.append(ClipRecord(id: string(stmt,0), kind: ClipKind(rawValue: string(stmt,1)) ?? .text, title: string(stmt,2), preview: string(stmt,3), sourceName: string(stmt,4), sourceBundle: string(stmt,5), created: Date(timeIntervalSince1970: sqlite3_column_double(stmt,6)), lastCopied: Date(timeIntervalSince1970: sqlite3_column_double(stmt,7)), copyCount: Int(sqlite3_column_int64(stmt,8)), favorite: sqlite3_column_int(stmt,9) != 0, byteCount: Int(sqlite3_column_int64(stmt,10))))
            result = sqlite3_step(stmt)
        }
        guard result == SQLITE_DONE else { throw error() }
        return rows
    }

    func content(_ id: String) throws -> (text: String, parts: [PastePart]) {
        let stmt = try prepare("SELECT body,payload FROM clips WHERE id=?"); defer { sqlite3_finalize(stmt) }
        bind(id, 1, stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt,1) else { throw RecolleError.invalidPayload }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt,1)))
        return (string(stmt,0), try JSONDecoder().decode([PastePart].self, from: data))
    }
    func text(_ id: String) throws -> String {
        let stmt = try prepare("SELECT body FROM clips WHERE id=?"); defer { sqlite3_finalize(stmt) }
        bind(id,1,stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw RecolleError.invalidPayload }
        return string(stmt,0)
    }
    func snapshot(query: String = "", filter: LibraryFilter = .all) throws -> LibrarySnapshot {
        let rows = try records(query: query,filter: filter)
        let stmt = try prepare("SELECT kind,COUNT(*),SUM(favorite) FROM clips GROUP BY kind")
        defer { sqlite3_finalize(stmt) }
        var counts = Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { ($0,0) })
        var result = sqlite3_step(stmt)
        while result == SQLITE_ROW {
            let count = Int(sqlite3_column_int64(stmt,1))
            if let type = LibraryFilter(rawValue: string(stmt,0)) { counts[type] = count }
            counts[.all,default: 0] += count
            counts[.favorites,default: 0] += Int(sqlite3_column_int64(stmt,2))
            result = sqlite3_step(stmt)
        }
        guard result == SQLITE_DONE else { throw error() }
        return LibrarySnapshot(records: rows,counts: counts)
    }
    func toggleFavorite(_ id: String) throws {
        let stmt = try prepare("UPDATE clips SET favorite=1-favorite WHERE id=?"); defer { sqlite3_finalize(stmt) }
        bind(id,1,stmt); try done(stmt)
    }
    func markReused(_ id: String, moveToTop: Bool = true) throws {
        let stmt = try prepare("UPDATE clips SET copy_count=copy_count+1,last_copied=?,list_order=CASE WHEN ? THEN ? ELSE list_order END WHERE id=?"); defer { sqlite3_finalize(stmt) }
        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(stmt,1,now); sqlite3_bind_int(stmt,2,moveToTop ? 1 : 0)
        sqlite3_bind_double(stmt,3,now); bind(id,4,stmt); try done(stmt)
    }
    func delete(_ id: String, checkpoint: Bool = true) throws {
        let stmt = try prepare("DELETE FROM clips WHERE id=?"); defer { sqlite3_finalize(stmt) }
        bind(id,1,stmt); try done(stmt)
        if checkpoint { try execute("PRAGMA wal_checkpoint(TRUNCATE)") }
    }
    func clear() throws {
        try execute("DELETE FROM clips")
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try execute("VACUUM")
    }
    func prune(days: Int, now: Date = Date()) throws {
        guard days > 0 else { return }
        let stmt = try prepare("DELETE FROM clips WHERE favorite=0 AND last_copied < ?"); defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt,1,now.addingTimeInterval(-Double(days)*86_400).timeIntervalSince1970); try done(stmt)
    }
}
