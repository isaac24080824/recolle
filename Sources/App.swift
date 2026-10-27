import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: HistoryModel!
    private var window: NSWindow!
    private var status: NSStatusItem!
    private let shortcut = GlobalHotKey()
    private var previousApp: NSRunningApplication?
    private var quickMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "fr.isaac.recolle"
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.regular)
        InteractionTrace.install()
        let args = CommandLine.arguments
        let verificationRoot: URL?
        if let index = args.firstIndex(of: "--verification-directory"), args.indices.contains(index + 1) {
            verificationRoot = URL(fileURLWithPath: args[index + 1],isDirectory: true)
        } else { verificationRoot = nil }
        model = HistoryModel(directory: verificationRoot)
        model.dismissAfterCopy = { [weak self] in
            guard let self, self.quickMode else { return }
            self.window.orderOut(nil); self.previousApp?.activate(options: [])
        }
        setupMenus()
        let host = NSHostingView(rootView: LibraryView(model: model))
        host.sizingOptions = [.minSize]
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1100,height: 720), styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Recolle"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 940,height: 590)
        window.contentView = host
        window.backgroundColor = NSColor(calibratedRed: 0.97,green: 0.965,blue: 0.95,alpha: 1)
        window.delegate = self
        window.setFrameAutosaveName("RecolleLibrary")
        window.center()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Recolle — historique du presse-papier")
            button.target = self; button.action = #selector(toggleWindow)
            button.sendAction(on: [.leftMouseUp,.rightMouseUp])
            button.toolTip = "Recolle · \(GlobalHotKey.display)"
        }
        shortcut.action = { [weak self] in self?.toggleQuick() }
        refreshShortcut()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(refreshShortcut), name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        model.start()
        showWindow(quick: false)
    }

    @objc private func refreshShortcut() { model.shortcutAvailable = shortcut.register() }

    private func setupMenus() {
        let main = NSMenu()
        let appRoot = NSMenuItem(); main.addItem(appRoot)
        let app = NSMenu(); appRoot.submenu = app
        let about = NSMenuItem(title: "À propos de Recolle", action: #selector(aboutApp), keyEquivalent: ""); about.target = self; app.addItem(about)
        app.addItem(.separator())
        let settings = NSMenuItem(title: "Réglages…", action: #selector(settingsApp), keyEquivalent: ","); settings.target = self; app.addItem(settings)
        app.addItem(.separator())
        app.addItem(withTitle: "Masquer Recolle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quitter Recolle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editRoot = NSMenuItem(); editRoot.title = "Édition"; main.addItem(editRoot)
        let edit = NSMenu(title: "Édition"); editRoot.submenu = edit
        edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowRoot = NSMenuItem(); windowRoot.title = "Fenêtre"; main.addItem(windowRoot)
        let win = NSMenu(title: "Fenêtre"); windowRoot.submenu = win
        win.addItem(withTitle: "Réduire", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc private func aboutApp() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Recolle", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.1", .credits: NSAttributedString(string: "Votre mémoire du copier-coller.\nApplication macOS locale et open source · Licence MIT.")])
    }
    @objc private func settingsApp() { showWindow(quick: false); model.showSettings = true }
    @objc private func pauseApp() { model.paused.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func toggleWindow() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = NSMenuItem(title: "Ouvrir Recolle", action: #selector(openApp), keyEquivalent: ""); open.target = self; menu.addItem(open)
            let pause = NSMenuItem(title: model.paused ? "Reprendre l’enregistrement" : "Mettre en pause", action: #selector(pauseApp), keyEquivalent: ""); pause.target = self; menu.addItem(pause)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quitter Recolle", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { toggleQuick() }
    }
    @objc private func openApp() { showWindow(quick: false) }
    private func toggleQuick() {
        if window.isKeyWindow && !model.showSettings { window.orderOut(nil); previousApp?.activate(options: []) }
        else { showWindow(quick: true) }
    }
    private func showWindow(quick: Bool) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        quickMode = quick
        model.prepareForOpening(quick: quick)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(quick: false); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.finishPendingWork { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func windowWillClose(_ notification: Notification) { if quickMode { previousApp?.activate(options: []) } }
}

@main
struct RecolleApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
