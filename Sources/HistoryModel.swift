import AppKit
import Combine
import ServiceManagement

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var records: [ClipRecord] = []
    @Published private(set) var counts: [LibraryFilter: Int] = [:]
    @Published var selectedID: String? { didSet { if selectedID != oldValue { InteractionTrace.selection(); loadSelection() } } }
    @Published var scrollRequest: String?
    @Published private(set) var preparedPreview: PreparedPreview?
    private(set) var selectedImage: NSImage?
    @Published var filter: LibraryFilter = .all { didSet { if filter != oldValue && !batching { reload() } } }
    @Published var query = "" { didSet { if query != oldValue && !batching { scheduleSearch() } } }
    @Published var paused: Bool { didSet { if paused != oldValue { defaults.set(paused,forKey: "paused"); lastChange = board.changeCount } } }
    @Published var retention: Int { didSet { if retention != oldValue { defaults.set(retention,forKey: "retention"); prune() } } }
    @Published var message: String?
    @Published var toast: String?
    @Published var shortcutAvailable = true
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var accessDenied = false
    @Published var showSettings = false
    @Published var showClear = false
    @Published var focusRequest = 0
    @Published private(set) var ready = false
    @Published var ignoredApps: [String] = []
    var dismissAfterCopy: (() -> Void)?
    private let worker: HistoryWorker
    private let board: NSPasteboard
    private let defaults: UserDefaults
    private var lastChange = 0
    private var timer: Timer?
    private var searchTask: DispatchWorkItem?
    private var snapshotTicket: WorkTicket?
    private var toastTask: DispatchWorkItem?
    private var ticks = 0
    private var nextPrune = Date().addingTimeInterval(3600)
    private var revision = 0
    private var selectionRevision = 0
    private var copyRevision = 0
    private var displayedQuery = ""
    private var displayedFilter: LibraryFilter = .all
    private var batching = false
    private var stopping = false
    private var recordsByID: [String: ClipRecord] = [:]
    private let ignoredAppsKey = "ignoredApps"
    var selected: ClipRecord? { selectedID.flatMap { recordsByID[$0] } }
    var total: Int { counts[.all,default: 0] }
    var selectedText: String { preparedPreview?.text ?? selected?.preview ?? "" }
    var selectedCharacterCount: Int? { preparedPreview?.characterCount }
    var selectedFiles: [FilePreview] { preparedPreview?.files ?? [] }
    var selectionLoading: Bool { selectedID != nil && preparedPreview == nil }

    init(directory: URL? = nil, board: NSPasteboard = .general, defaults: UserDefaults = .standard, worker: HistoryWorker? = nil) {
        self.board = board; self.defaults = defaults
        paused = defaults.bool(forKey: "paused")
        retention = defaults.integer(forKey: "retention")
        ignoredApps = defaults.stringArray(forKey: ignoredAppsKey) ?? []
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("Recolle",isDirectory: true)
        self.worker = worker ?? HistoryWorker(url: root.appendingPathComponent("history.sqlite"))
        lastChange = board.changeCount
        prune()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.15,repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        timer.tolerance = 0.025
        RunLoop.main.add(timer,forMode: .common); self.timer = timer
    }

    func poll() {
        guard !stopping else { return }
        ticks += 1
        if Date() >= nextPrune { nextPrune = Date().addingTimeInterval(3600); prune() }
        let change = board.changeCount
        if ticks % 7 == 1 || change != lastChange, #available(macOS 15.4, *) {
            let denied = board.accessBehavior == .alwaysDeny
            if accessDenied != denied { accessDenied = denied }
        }
        guard change != lastChange else { return }
        lastChange = change
        guard !paused, !accessDenied else { return }
        let source = NSWorkspace.shared.frontmostApplication
        let bundle = source?.bundleIdentifier ?? ""
        guard bundle != Bundle.main.bundleIdentifier, !ignoredApps.contains(bundle) else { return }
        do {
            guard let capture = try CaptureReader.read(board,sourceName: source?.localizedName ?? "Application",sourceBundle: bundle) else { return }
            guard board.changeCount == change else { lastChange = change; return }
            changeHistory { _ = try $0.save(capture) }
        } catch { message = error.localizedDescription }
    }

    func reload() {
        snapshotTicket?.cancel()
        revision += 1
        let current = revision, query = query, filter = filter, ticket = WorkTicket()
        snapshotTicket = ticket
        worker.snapshot(query: query,filter: filter,ticket: ticket) { [weak self] result in
            guard let self, self.revision == current else { return }
            self.ready = true
            switch result {
            case .success(let snapshot): if let snapshot { self.apply(snapshot,query: query,filter: filter) }
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }

    private func apply(_ snapshot: LibrarySnapshot, query: String, filter: LibraryFilter) {
        guard !stopping else { return }
        displayedQuery = query; displayedFilter = filter
        if counts != snapshot.counts { counts = snapshot.counts }
        if records != snapshot.records {
            recordsByID = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id,$0) })
            records = snapshot.records
        }
        if selectedID == nil || selectedID.flatMap({ recordsByID[$0] }) == nil { selectedID = records.first?.id; scrollRequest = selectedID }
    }

    private func changeHistory(invalidateContent: Bool = true, _ operation: @escaping (HistoryDatabase) throws -> Void) {
        snapshotTicket?.cancel()
        revision += 1
        let current = revision, query = query, filter = filter
        worker.mutate(query: query,filter: filter,invalidateContent: invalidateContent,operation: operation) { [weak self] result in
            guard let self else { return }
            self.ready = true
            switch result {
            case .success(let snapshot):
                if self.revision == current { self.apply(snapshot,query: query,filter: filter) }
            case .failure(let error): self.message = error.localizedDescription; self.reload()
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel(); snapshotTicket?.cancel()
        // Invalidate a result already in flight as soon as the query changes.
        revision += 1
        let task = DispatchWorkItem { [weak self] in self?.reload() }
        searchTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035,execute: task)
    }
    func prepareForOpening(quick: Bool) {
        if selected?.kind == .files { loadSelection() }
        guard quick, !query.isEmpty || filter != .all else { return }
        searchTask?.cancel()
        batching = true; query = ""; filter = .all; batching = false
        reload()
    }
    func finishPendingWork(_ completion: @escaping @MainActor () -> Void) {
        stopping = true
        timer?.invalidate(); timer = nil
        searchTask?.cancel(); snapshotTicket?.cancel()
        // The second barrier also includes writes enqueued by a pending copy's
        // main-thread completion. A normal Quit must never drop a captured item.
        worker.perform({ _ in () }) { [worker] _ in
            worker.perform({ _ in () }) { _ in completion() }
        }
    }
    func select(_ id: String) {
        if selectedID != id { selectedID = id }
        else if selected?.kind == .files { loadSelection() }
    }
    private func loadSelection() {
        selectionRevision += 1
        let current = selectionRevision
        selectedImage = nil
        preparedPreview = nil
        guard let record = selected else { return }
        if let cached = worker.cachedPreview(id: record.id,kind: record.kind) { setPreview(cached); return }
        worker.preview(id: record.id,kind: record.kind) { [weak self] result in
            guard let self, self.selectionRevision == current, self.selectedID == record.id else { return }
            switch result {
            case .success(let preview): self.setPreview(preview)
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }
    private func setPreview(_ preview: PreparedPreview) {
        selectedImage = preview.image.map { NSImage(cgImage: $0,size: .zero) }
        preparedPreview = preview
    }

    func copy(_ record: ClipRecord? = nil, plain: Bool = false, keepWindowOpen: Bool = false) {
        searchTask?.cancel()
        copyRevision += 1
        let current = copyRevision
        let id = record?.id ?? (displayedQuery == query && displayedFilter == filter ? selectedID : nil)
        worker.copy(id: id,query: query,filter: filter) { [weak self] result in
            guard let self, self.copyRevision == current else { return }
            switch result {
            case .success(let value):
                guard let value else { self.reload(); return }
                guard CaptureReader.write(value.content.parts,text: value.content.text,plain: plain,to: self.board) else { self.message = RecolleError.invalidPayload.localizedDescription; return }
                self.lastChange = self.board.changeCount
                self.notify("Copié ! Collez avec ⌘V.")
                if !keepWindowOpen { self.dismissAfterCopy?() }
                self.changeHistory(invalidateContent: false) { try $0.markReused(value.id,moveToTop: !keepWindowOpen) }
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }
    func favorite(_ record: ClipRecord? = nil) {
        guard let record = record ?? selected else { return }
        changeHistory(invalidateContent: false) { try $0.toggleFavorite(record.id) }
    }
    func delete(_ record: ClipRecord? = nil) {
        guard let record = record ?? selected else { return }
        copyRevision += 1
        changeHistory { try $0.delete(record.id) }
    }
    func clear() {
        copyRevision += 1
        lastChange = board.changeCount
        changeHistory { try $0.clear() }
        notify("Effacement de l’historique…")
    }
    private func prune() {
        let days = retention
        changeHistory { try $0.prune(days: days) }
    }
    func notify(_ text: String) {
        toastTask?.cancel(); toast = text
        let task = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 3,execute: task)
    }
    func moveSelection(_ offset: Int) {
        guard !records.isEmpty else { return }
        let index = records.firstIndex { $0.id == selectedID } ?? 0
        selectedID = records[min(max(index + offset,0),records.count-1)].id
        scrollRequest = selectedID
    }
    func toggleLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { message = "Le démarrage automatique n’a pas pu être modifié. \(error.localizedDescription)" }
    }
    func addIgnoredApp(_ url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else { message = "Choisissez une application .app."; return }
        if !ignoredApps.contains(id) { ignoredApps.append(id); ignoredApps.sort(); saveIgnored() }
    }
    func removeIgnoredApp(_ id: String) { ignoredApps.removeAll { $0 == id }; saveIgnored() }
    private func saveIgnored() { defaults.set(ignoredApps,forKey: ignoredAppsKey) }
    func openPrivacy() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!) }
}
