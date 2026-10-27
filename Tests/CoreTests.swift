import AppKit
import Foundation

@main
struct CoreTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw NSError(domain: "RecolleTests",code: 1,userInfo: [NSLocalizedDescriptionKey: name]) }
        checks += 1
    }
    static func capture(_ text: String, source: String = "Éditeur") -> Capture {
        Capture(kind: .text,text: text,title: text,parts: [PastePart(representations: [NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)])],sourceName: source,sourceBundle: "test.editor")
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecolleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite")
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        var db: HistoryDatabase? = try HistoryDatabase(url: url)
        let original = "Première ligne\nDeuxième ligne avec café ☕️  "
        let id = try db!.save(capture(original),at: t)
        try expect(try db!.records().count == 1,"Une nouvelle copie est conservée")
        try expect(try db!.content(id).text == original,"Sauts de ligne, accents et espaces conservés")
        try expect(try db!.records(query: "CAFE").count == 1,"Recherche sans accent et sans casse")
        try expect(try db!.records(query: "editeur ligne").count == 1,"Recherche de plusieurs mots et application source")
        try expect(try db!.records(query: "introuvable").isEmpty,"Recherche sans résultat")
        try expect(try db!.records(filter: .image).isEmpty,"Filtre par type")
        try db!.toggleFavorite(id)
        let duplicateID = try db!.save(capture(original,source: "Navigateur"),at: t.addingTimeInterval(10))
        let duplicate = try db!.records().first!
        try expect(duplicateID == id && duplicate.copyCount == 2 && duplicate.favorite,"Doublon regroupé sans perdre le favori")
        try expect(duplicate.created == t && duplicate.lastCopied == t.addingTimeInterval(10),"Dates de première et dernière copie")
        try expect(duplicate.sourceName == "Navigateur","Source actualisée à la dernière copie")
        try expect(try db!.records(filter: .favorites).count == 1,"Filtre favoris")
        try expect(try db!.records(query: "navigateur").count == 1,"Recherche de la nouvelle source")
        db = nil
        db = try HistoryDatabase(url: url)
        try expect(try db!.content(id).text == original,"Persistance après réouverture")
        try expect(try db!.records().first!.favorite,"Favoris conservés après réouverture")
        try db!.markReused(id)
        try expect(try db!.records().first!.copyCount == 3,"Recopie comptabilisée")
        _ = try db!.save(capture("ancien"),at: t)
        try db!.prune(days: 7,now: t.addingTimeInterval(100*86_400))
        try expect(try db!.records().count == 1,"Purge datée préserve les favoris")
        try db!.clear()
        try expect(try db!.records().isEmpty,"Effacement complet, favoris compris")
        let nulText = "avant\0après"
        let nulID = try db!.save(capture(nulText))
        try expect(try db!.content(nulID).text == nulText,"Caractère nul conservé sans tronquer le texte")
        try db!.delete(nulID)
        try expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600,"Fichier privé au compte Mac")

        let capped = try HistoryDatabase(url: root.appendingPathComponent("capped.sqlite"),maxCount: 2)
        let favoriteID = try capped.save(capture("favori"),at: t)
        try capped.toggleFavorite(favoriteID)
        _ = try capped.save(capture("à retirer"),at: t.addingTimeInterval(1))
        _ = try capped.save(capture("nouveau"),at: t.addingTimeInterval(2))
        let kept = try capped.records()
        try expect(kept.count == 2 && kept.contains { $0.id == favoriteID } && !kept.contains { $0.title == "à retirer" },"Capacité : plus ancien retiré, favori préservé")
        let newestID = kept.first!.id
        try capped.toggleFavorite(newestID)
        var refused = false
        do { _ = try capped.save(capture("refusé")) } catch RecolleError.capacity { refused = true }
        try expect(refused && (try capped.records().count) == 2,"Capacité occupée : transaction annulée sans perdre de favoris")
        let byteCap = try HistoryDatabase(url: root.appendingPathComponent("bytes.sqlite"),maxBytes: 1_000)
        var bytesRefused = false
        do { _ = try byteCap.save(capture(String(repeating: "a",count: 2_000))) } catch RecolleError.capacity { bytesRefused = true }
        try expect(bytesRefused && (try byteCap.records().isEmpty),"Limite d’espace : aucune écriture partielle")

        // A private named pasteboard exercises AppKit without touching the user's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        try expect(board.setString(original,forType: .string),"Écriture sur le presse-papier de test")
        let textCapture = try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test")!
        try expect(textCapture.kind == .text && textCapture.text == original,"Lecture réelle NSPasteboard texte")
        try expect(CaptureReader.write(textCapture.parts,text: original,plain: false,to: board),"Réécriture des formats originaux")
        try expect(board.string(forType: .string) == original,"Recopie exacte du texte")
        board.clearContents(); board.setString("https://example.com/café?q=bonjour",forType: .string)
        try expect(try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test")?.kind == .link,"Détection des liens")
        board.clearContents(); board.setString("https://example.com un commentaire",forType: .string)
        try expect(try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test")?.kind == .text,"Texte contenant un lien")
        board.clearContents(); board.setString("  \n ",forType: .string)
        try expect(try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test") == nil,"Copie vide ignorée")
        for marker in CaptureReader.ignoredTypes {
            board.clearContents(); board.setString("ne pas enregistrer",forType: .string); board.setData(Data(),forType: .init(marker))
            try expect(try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test") == nil,"Marqueur confidentiel ou transitoire ignoré : \(marker)")
        }
        board.clearContents(); board.setString("secret",forType: .string)
        try expect(try CaptureReader.read(board,sourceName: "1Password",sourceBundle: "com.1password.1password") == nil,"Gestionnaire de mots de passe exclu")
        board.clearContents()
        let normal = NSPasteboardItem(); normal.setString("normal",forType: .string)
        let secret = NSPasteboardItem(); secret.setString("secret",forType: .string); secret.setData(Data(),forType: .init("org.nspasteboard.ConcealedType"))
        board.writeObjects([normal,secret])
        try expect(try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test") == nil,"Confidentialité vérifiée sur tous les éléments")
        board.clearContents()
        let fileURLs = [URL(fileURLWithPath: "/private/tmp/document un.pdf"),URL(fileURLWithPath: "/private/tmp/image.png")]
        board.writeObjects(fileURLs as [NSURL])
        let files = try CaptureReader.read(board,sourceName: "Finder",sourceBundle: "com.apple.finder")!
        try expect(files.kind == .files && files.text.split(separator: "\n").count == 2,"Copie de plusieurs références de fichiers")
        _ = CaptureReader.write(files.parts,text: files.text,plain: false,to: board)
        try expect(board.pasteboardItems?.count == 2 && board.pasteboardItems?.first?.string(forType: .fileURL) == fileURLs[0].absoluteString,"Restauration des deux fichiers dans le presse-papier")
        board.clearContents()
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 2,pixelsHigh: 2,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        let png = pixels.representation(using: .png,properties: [:])!
        board.setData(png,forType: .png)
        let image = try CaptureReader.read(board,sourceName: "Aperçu",sourceBundle: "com.apple.Preview")!
        let imageID = try db!.save(image)
        let imageContent = try db!.content(imageID)
        _ = CaptureReader.write(imageContent.parts,text: imageContent.text,plain: false,to: board)
        try expect(image.kind == .image && board.data(forType: .png) == png,"Image conservée et recopiée sans altération")
        board.clearContents()
        let imageItem = NSPasteboardItem(); imageItem.setData(png,forType: .png); imageItem.setData(Data(count: CaptureReader.maxBytes + 1),forType: .tiff)
        board.writeObjects([imageItem])
        let imageWithFallback = try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test")!
        try expect(imageWithFallback.parts.first?.representations[NSPasteboard.PasteboardType.tiff.rawValue] == nil,"Copie PNG : représentation TIFF redondante exclue")
        board.clearContents()
        let rich = NSPasteboardItem()
        rich.setString("Bonjour",forType: .string)
        let html = Data("<b>Bonjour</b>".utf8); rich.setData(html,forType: .html)
        board.writeObjects([rich])
        let richCapture = try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test")!
        let richID = try db!.save(richCapture)
        let richContent = try db!.content(richID)
        _ = CaptureReader.write(richContent.parts,text: richContent.text,plain: false,to: board)
        try expect(board.data(forType: .html) == html,"Mise en forme HTML préservée")
        _ = CaptureReader.write(richContent.parts,text: richContent.text,plain: true,to: board)
        try expect(board.string(forType: .string) == "Bonjour" && board.data(forType: .html) == nil,"Recopie sans mise en forme")
        try db!.delete(richID)
        try expect(try db!.records().count == 1,"Suppression ciblée")
        board.clearContents(); board.setData(Data(count: CaptureReader.maxBytes + 1),forType: .png)
        var oversize = false
        do { _ = try CaptureReader.read(board,sourceName: "Test",sourceBundle: "test") } catch { oversize = true }
        try expect(oversize,"Copie trop volumineuse refusée")
        print("\(checks) vérifications réussies. Aucun accès au presse-papier personnel.")
    }
}
