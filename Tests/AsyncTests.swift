import AppKit
import Combine
import Foundation

@main
struct AsyncTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ description: String) throws {
        guard try value() else { throw NSError(domain: "RecolleAsyncTests",code: 1,userInfo: [NSLocalizedDescriptionKey: description]) }
        checks += 1
    }
    @MainActor static func wait(_ description: String, timeout: TimeInterval = 8, until predicate: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline { _ = RunLoop.main.run(mode: .default,before: Date().addingTimeInterval(0.003)) }
        try expect(predicate(),description)
    }
    static func capture(_ text: String, html: String? = nil) -> Capture {
        var data = ["public.utf8-plain-text": Data(text.utf8)]
        if let html { data["public.html"] = Data(html.utf8) }
        return Capture(kind: .text,text: text,title: String(text.prefix(80)),parts: [PastePart(representations: data)],sourceName: "Éditeur",sourceBundle: "test.editor")
    }
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecolleAsync-\(UUID().uuidString)")
        let suite = "RecolleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let url = root.appendingPathComponent("history.sqlite")
        var seed: HistoryDatabase? = try HistoryDatabase(url: url)
        let alpha = "Alpha — café avec mise en forme"
        let beta = "Bêta — deuxième texte"
        let large = String(repeating: "Une ligne de très grand texte, café ☕️.\n",count: 50_000)
        let alphaID = try seed!.save(capture(alpha,html: "<b>\(alpha)</b>"),at: Date(timeIntervalSince1970: 1))
        let betaID = try seed!.save(capture(beta),at: Date(timeIntervalSince1970: 2))
        let largeID = try seed!.save(capture(large),at: Date(timeIntervalSince1970: 3))
        try seed!.toggleFavorite(alphaID)
        let snapshot = try seed!.snapshot()
        let betaRecord = snapshot.records.first { $0.id == betaID }!
        try expect(snapshot.counts[.all] == 3 && snapshot.counts[.favorites] == 1 && snapshot.counts[.text] == 3,"Comptages agrégés complets")
        try expect(try seed!.snapshot(query: "cafe alpha",filter: .favorites).records.first?.id == alphaID,"Recherche complète avec accents et favoris")
        seed = nil
        let worker = HistoryWorker(url: url)
        let model = HistoryModel(directory: root,board: board,defaults: defaults,worker: worker)
        var dismissals = 0
        model.dismissAfterCopy = { dismissals += 1 }
        try wait("Chargement initial asynchrone et aperçu complet") { model.ready && model.records.count == 3 && model.preparedPreview?.text == large }
        try expect(model.selectedCharacterCount == large.count,"Texte volumineux conservé intégralement")
        try expect(worker.cachedPreview(id: largeID,kind: .text)?.text == large,"Mise en cache du texte intégral")

        var backgroundDone = false
        var backgroundWasOffMain = false
        worker.perform({ _ in
            let offMain = !Thread.isMainThread
            Thread.sleep(forTimeInterval: 0.18)
            return offMain
        }) { result in backgroundWasOffMain = (try? result.get()) == true; backgroundDone = true }
        let start = DispatchTime.now().uptimeNanoseconds
        model.selectedID = alphaID
        model.selectedID = betaID
        let selectionMS = Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
        try expect(selectionMS < 30,"Les sélections ne bloquent pas sur les accès disque")
        try wait("L’aperçu ancien ne remplace jamais la dernière sélection") { backgroundDone && model.preparedPreview?.text == beta }
        try expect(backgroundWasOffMain,"Opérations de stockage exécutées hors du fil de l’interface")
        let betaPreview = model.preparedPreview!
        model.selectedID = largeID
        model.selectedID = betaID
        try expect(model.preparedPreview === betaPreview,"Retour immédiat sur un aperçu déjà consulté")

        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        for _ in 0..<30 { model.poll() }
        try expect(changes == 0,"Aucun rafraîchissement inutile quand le presse-papier ne change pas")
        observation.cancel()

        model.query = "ne correspond pas"
        model.query = "alpha cafe"
        model.query = "bêta"
        try wait("Seule la dernière recherche rapide est affichée") { model.records.count == 1 && model.records.first?.id == betaID }
        try expect(model.counts[.all] == 3 && model.counts[.favorites] == 1,"Comptages indépendants de la recherche")
        model.query = "alpha"
        model.copy()
        try wait("Entrée pendant une recherche recopie le bon résultat") { board.string(forType: .string) == alpha }
        try expect(board.data(forType: .html) == Data("<b>\(alpha)</b>".utf8),"Formats HTML conservés pendant la recopie asynchrone")
        try wait("La recopie reste comptabilisée") { model.records.first?.id == alphaID && model.records.first?.copyCount == 2 }
        model.copy(plain: true)
        try wait("Recopie en texte brut") { board.string(forType: .string) == alpha && board.data(forType: .html) == nil }
        try wait("Compteur après recopie brute") { model.records.first?.copyCount == 3 }
        try expect(dismissals == 2,"La recopie habituelle conserve sa fermeture automatique")
        model.copy(betaRecord,keepWindowOpen: true)
        try wait("Copie rapide d’une autre ligne sans la sélectionner") { board.string(forType: .string) == beta }
        try expect(dismissals == 2,"La copie rapide ne demande jamais de fermer la fenêtre")
        try expect(model.selectedID == alphaID && model.query == "alpha","La copie rapide conserve la sélection et la recherche")

        model.filter = .favorites
        try wait("Filtre favoris après mise à jour") { model.records.count == 1 && model.records.first?.favorite == true }
        model.favorite()
        try wait("Retrait du favori et recherche cohérents") { model.records.isEmpty && model.counts[.favorites] == 0 }
        model.prepareForOpening(quick: true)
        try wait("Ouverture rapide rétablit l’historique entier") { model.query.isEmpty && model.filter == .all && model.records.count == 3 }
        try expect(model.records.first { $0.id == betaID }?.copyCount == 2,"La copie rapide conserve le compteur de réutilisation")
        try expect(model.records.map(\.id) == [alphaID,largeID,betaID],"Une copie rapide ne remonte pas la ligne dans la liste")
        try expect(model.records.first { $0.id == betaID }!.lastCopied > betaRecord.lastCopied,"La dernière utilisation reste actualisée pour la conservation")
        let stableOrder = model.records.map(\.id)
        model.copy(betaRecord,keepWindowOpen: true)
        try wait("Une deuxième copie rapide est comptabilisée") { model.records.first { $0.id == betaID }?.copyCount == 3 }
        try expect(model.records.map(\.id) == stableOrder,"Plusieurs copies rapides conservent exactement l’ordre de la liste")
        let orderAfterRestart = try HistoryDatabase(url: url)
        try expect(try orderAfterRestart.records().map(\.id) == stableOrder,"L’ordre reste conservé après réouverture")
        model.copy(betaRecord)
        try wait("La recopie classique conserve sa remontée habituelle") { model.records.first?.id == betaID && model.records.first?.copyCount == 4 }

        model.paused = true
        board.clearContents(); board.setString("Copie pendant la pause",forType: .string); model.poll()
        try expect(model.records.count == 3,"Pause : aucune copie ajoutée")
        model.paused = false; model.poll()
        try expect(model.records.count == 3,"Reprise : aucune récupération des copies privées pendant la pause")
        board.clearContents(); board.setString("Nouvelle copie après reprise",forType: .string); model.poll()
        try wait("Collecte et sauvegarde asynchrones après reprise") { model.total == 4 }

        model.selectedID = betaID
        model.delete()
        try wait("Suppression ciblée asynchrone") { model.total == 3 && !model.records.contains { $0.id == betaID } }
        model.clear()
        try wait("Effacement complet après les opérations en attente") { model.total == 0 && model.records.isEmpty && model.selectedID == nil }
        let reopened = try HistoryDatabase(url: url)
        try expect(try reopened.records().isEmpty,"Effacement conservé après réouverture")
        var drained = false
        worker.perform({ _ in Thread.sleep(forTimeInterval: 0.1) }) { _ in }
        board.clearContents(); board.setString("Copie avant fermeture",forType: .string); model.poll()
        model.finishPendingWork { drained = true }
        try wait("Fermeture : attente des écritures encore en cours") { drained }
        try expect(try reopened.records().first?.title == "Copie avant fermeture","Dernière copie sauvegardée avant de quitter")

        let assetURL = root.appendingPathComponent("assets.sqlite")
        let assets = try HistoryDatabase(url: assetURL)
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 2,pixelsHigh: 2,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        let png = pixels.representation(using: .png,properties: [:])!
        let imageID = try assets.save(Capture(kind: .image,text: "Image",title: "Image",parts: [PastePart(representations: ["public.png": png])],sourceName: "Test",sourceBundle: "test"))
        let fileURL = root.appendingPathComponent("document.txt")
        try Data("fichier de test".utf8).write(to: fileURL)
        let fileID = try assets.save(Capture(kind: .files,text: fileURL.absoluteString,title: "document.txt",parts: [PastePart(representations: ["public.file-url": Data(fileURL.absoluteString.utf8)])],sourceName: "Finder",sourceBundle: "com.apple.finder"))
        let assetWorker = HistoryWorker(url: assetURL)
        var imagePreview: PreparedPreview?
        assetWorker.preview(id: imageID,kind: .image) { imagePreview = try? $0.get() }
        try wait("Décodage d’image en arrière-plan et dimensions conservées") { imagePreview?.image?.width == 2 && imagePreview?.image?.height == 2 }
        var imageCopy: PreparedCopy?
        assetWorker.copy(id: imageID,query: "",filter: .all) { imageCopy = (try? $0.get())?.content }
        try wait("Original PNG intact après préparation de l’aperçu") { imageCopy?.parts.first?.representations["public.png"] == png }
        var filePreview: PreparedPreview?
        assetWorker.preview(id: fileID,kind: .files) { filePreview = try? $0.get() }
        try wait("Aperçu des références de fichiers") { filePreview?.files.first?.exists == true }
        try FileManager.default.moveItem(at: fileURL,to: root.appendingPathComponent("document-déplacé.txt"))
        filePreview = nil
        assetWorker.preview(id: fileID,kind: .files) { filePreview = try? $0.get() }
        try wait("Déplacement de fichier détecté sans cache périmé") { filePreview?.files.first?.exists == false }
        try expect(model.message == nil,"Aucune erreur dans les parcours asynchrones")
        print("\(checks) vérifications asynchrones réussies ; sélections en \(String(format: "%.3f",selectionMS)) ms pendant un accès disque simulé de 180 ms.")
    }
}
