import AppKit
import SwiftUI

struct InstantRowHitArea: NSViewRepresentable {
    let record: ClipRecord
    let select: () -> Void
    let copy: (Bool) -> Void
    let favorite: () -> Void
    let delete: () -> Void

    func makeNSView(context: Context) -> HitView { HitView() }
    func updateNSView(_ view: HitView, context: Context) {
        view.select = select; view.copy = copy; view.favorite = favorite; view.delete = delete
        view.record = record
    }
    final class MenuAction: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
    final class HitView: NSView {
        var record: ClipRecord?
        var select: (() -> Void)?
        var copy: ((Bool) -> Void)?
        var favorite: (() -> Void)?
        var delete: (() -> Void)?
        private var menuActions: [MenuAction] = []
        override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(false) }
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control), let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu,with: event,for: self); return
            }
            select?()
            if event.clickCount == 2 { copy?(false) }
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            select?()
            let menu = NSMenu(); menuActions = []
            func item(_ title: String, _ action: @escaping () -> Void) {
                let target = MenuAction(action); menuActions.append(target)
                let item = NSMenuItem(title: title,action: #selector(MenuAction.invoke),keyEquivalent: "")
                item.target = target; menu.addItem(item)
            }
            item("Recopier") { [weak self] in self?.copy?(false) }
            if record?.kind == .text || record?.kind == .link {
                item("Recopier sans mise en forme") { [weak self] in self?.copy?(true) }
            }
            item(record?.favorite == true ? "Retirer des favoris" : "Ajouter aux favoris") { [weak self] in self?.favorite?() }
            menu.addItem(.separator())
            item("Supprimer") { [weak self] in self?.delete?() }
            return menu
        }
    }
}

// TextKit lays out the visible region instead of making SwiftUI shape an entire
// multi-megabyte Text value on every selection or state update. Text stays selectable.
struct NativeTextPreview: NSViewRepresentable {
    let id: String
    let text: String
    let fontSize: CGFloat
    final class Coordinator { var id = ""; var text = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 20,height: 20)
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.layoutManager?.allowsNonContiguousLayout = true
        view.textColor = NSColor(calibratedRed: 0.17,green: 0.18,blue: 0.20,alpha: 1)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6
        view.defaultParagraphStyle = paragraph
        view.setAccessibilityLabel("Contenu de la copie sélectionnée")
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.id != id || context.coordinator.text != text else { return }
        let view = scroll.documentView as! NSTextView
        view.font = NSFont.systemFont(ofSize: fontSize)
        view.string = text
        context.coordinator.id = id; context.coordinator.text = text
        view.scrollRangeToVisible(NSRange(location: 0,length: 0))
    }
}

enum AppIconCache {
    private static let images = NSCache<NSString,NSImage>()
    static func image(for bundle: String) -> NSImage? {
        if let image = images.object(forKey: bundle as NSString) { return image }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app",accessibilityDescription: "Application")
        if let image { images.setObject(image,forKey: bundle as NSString) }
        return image
    }
}
