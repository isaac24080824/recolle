import SwiftUI
import AppKit

private enum Palette {
    static let background = Color(red: 0.984,green: 0.980,blue: 0.969)
    static let sidebar = Color(red: 0.954,green: 0.949,blue: 0.933)
    static let ink = Color(red: 0.17,green: 0.18,blue: 0.20)
    static let muted = Color(red: 0.47,green: 0.48,blue: 0.50)
    static let line = Color(red: 0.89,green: 0.88,blue: 0.86)
    static let accent = Color(red: 0.40,green: 0.32,blue: 0.83)
    static let pale = Color(red: 0.926,green: 0.91,blue: 0.985)
    static let green = Color(red: 0.20,green: 0.53,blue: 0.37)
}

struct LibraryView: View {
    @ObservedObject var model: HistoryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                if model.paused { banner("L’enregistrement est en pause.", symbol: "pause.circle", button: "Reprendre") { model.paused = false } }
                if model.accessDenied { banner("macOS bloque l’accès au presse-papier.", symbol: "lock", button: "Autoriser dans Réglages") { model.openPrivacy() } }
                if let message = model.message {
                    banner(message, symbol: "exclamationmark.circle", button: "Fermer") { model.message = nil }
                }
                HStack(spacing: 0) {
                    history.frame(minWidth: 285,idealWidth: 350,maxWidth: 380)
                    Rectangle().fill(Palette.line).frame(width: 1)
                    preview.frame(minWidth: 310,maxWidth: .infinity)
                }
                footer
            }
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(.light)
        .frame(minWidth: 940,minHeight: 560)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13,weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal,18).padding(.vertical,12)
                    .background(Palette.ink,in: Capsule()).padding(.bottom,52)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .alert("Effacer tout l’historique ?", isPresented: $model.showClear) {
            Button("Annuler",role: .cancel) { }
            Button("Tout effacer",role: .destructive) { model.clear() }
        } message: { Text("Tous les éléments, y compris les favoris, seront supprimés de Recolle. Le presse-papier actuel restera disponible.") }
        .background {
            Group {
                Button("") { searchFocused = true }.keyboardShortcut("f",modifiers: .command)
                Button("") { model.copy() }.keyboardShortcut(.return,modifiers: [])
                Button("") { model.favorite() }.keyboardShortcut("d",modifiers: .command)
                Button("") { model.copy(plain: true) }.keyboardShortcut("c",modifiers: [.command,.shift])
            }.hidden().accessibilityHidden(true)
        }
        .onChange(of: model.focusRequest) { _,_ in searchFocused = true }
        .onMoveCommand { direction in
            if direction == .down { model.moveSelection(1) }
            if direction == .up { model.moveSelection(-1) }
        }
        .onExitCommand {
            if !model.query.isEmpty { model.query = "" } else { NSApp.keyWindow?.performClose(nil) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading,spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Palette.accent).frame(width: 35,height: 35)
                    Image(systemName: "square.on.square").font(.system(size: 17,weight: .semibold)).foregroundStyle(.white)
                }
                Text("Recolle").font(.system(size: 23,weight: .bold,design: .rounded)).tracking(-0.6)
            }.padding(.top,44).padding(.bottom,7)
            Text("La mémoire de vos copies.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.bottom,34)
            Text("BIBLIOTHÈQUE").font(.system(size: 9,weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.bottom,12)
            ForEach([LibraryFilter.all,.favorites]) { navigationItem($0) }
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical,20)
            Text("PAR TYPE").font(.system(size: 9,weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.bottom,12)
            ForEach([LibraryFilter.text,.link,.image,.files]) { navigationItem($0) }
            Spacer(minLength: 24)
            VStack(alignment: .leading,spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(model.paused ? Color.orange : Palette.green).frame(width: 6,height: 6)
                    Text(model.paused ? "En pause" : "Enregistrement actif").font(.system(size: 11,weight: .medium))
                }
                Button { model.paused.toggle() } label: {
                    Label(model.paused ? "Reprendre" : "Mettre en pause", systemImage: model.paused ? "play" : "pause")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.buttonStyle(.plain)
            }.padding(12).frame(maxWidth: .infinity,alignment: .leading).background(.white.opacity(0.65),in: RoundedRectangle(cornerRadius: 11))
            Button { model.showSettings = true } label: {
                HStack { Image(systemName: "slider.horizontal.3"); Text("Réglages"); Spacer(); Text("⌘,").font(.system(size: 10)) }
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical,18)
            }.buttonStyle(.plain)
        }.padding(.horizontal,18).background(Palette.sidebar)
    }

    private func navigationItem(_ filter: LibraryFilter) -> some View {
        Button { model.filter = filter } label: {
            HStack(spacing: 9) {
                Image(systemName: filter.symbol).font(.system(size: 13)).frame(width: 18)
                Text(filter.title).font(.system(size: 12,weight: model.filter == filter ? .semibold : .regular))
                Spacer(minLength: 0)
                Text("\(model.counts[filter,default: 0])").font(.system(size: 10,weight: .medium)).monospacedDigit()
                    .foregroundStyle(model.filter == filter ? Palette.accent : Palette.muted)
            }.foregroundStyle(model.filter == filter ? Palette.accent : Palette.ink.opacity(0.8))
                .padding(.horizontal,10).padding(.vertical,10)
                .background(model.filter == filter ? Palette.pale : .clear,in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal,-5).padding(.bottom,3)
            .accessibilityLabel("\(filter.title), \(model.counts[filter,default: 0]) élément\(model.counts[filter,default: 0] == 1 ? "" : "s")")
    }

    private var header: some View {
        VStack(alignment: .leading,spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading,spacing: 5) {
                    Text(model.filter == .all ? "Votre presse-papier, en mieux." : model.filter.title)
                        .font(.system(size: 25,weight: .semibold)).tracking(-0.6)
                    Text("Copiez au fil de la journée. Retrouvez tout ici.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Label("Sur ce Mac",systemImage: "internaldrive").font(.system(size: 10,weight: .medium))
                    .foregroundStyle(Palette.muted).padding(.horizontal,10).padding(.vertical,7)
                    .background(.white,in: Capsule()).overlay(Capsule().stroke(Palette.line,lineWidth: 1))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.muted)
                TextField("Rechercher un texte, un lien, une application…",text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .onSubmit { model.copy() }
                    .accessibilityLabel("Rechercher dans l’historique")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                } else { Text("⌘ F").font(.system(size: 10,weight: .medium)).foregroundStyle(Palette.muted).padding(4).background(Palette.sidebar,in: RoundedRectangle(cornerRadius: 4)) }
            }.padding(.horizontal,14).frame(height: 43).background(.white,in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(searchFocused ? Palette.accent.opacity(0.45) : Palette.line,lineWidth: 1))
        }.padding(.horizontal,28).padding(.top,44).padding(.bottom,22)
    }

    private var history: some View {
        VStack(alignment: .leading,spacing: 0) {
            HStack {
                Text(model.query.isEmpty ? "DERNIÈRES COPIES" : "RÉSULTATS").font(.system(size: 9,weight: .semibold)).tracking(1.2)
                Spacer()
                Text("\(model.records.count) élément\(model.records.count == 1 ? "" : "s")").font(.system(size: 10))
            }.foregroundStyle(Palette.muted).padding(.horizontal,22).padding(.vertical,14)
            if model.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 26,weight: .light)).foregroundStyle(Palette.accent.opacity(0.65))
                    Text(emptyTitle).font(.system(size: 14,weight: .semibold))
                    Text(emptySubtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4)
                    if !model.query.isEmpty { Button("Effacer la recherche") { model.query = "" }.buttonStyle(.borderless) }
                }.padding(26).frame(maxWidth: .infinity,maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.records) { record in
                                HStack(spacing: 0) {
                                    ClipRow(record: record)
                                        .contentShape(Rectangle())
                                        .overlay(InstantRowHitArea(record: record,select: { model.select(record.id) },copy: { model.copy(record,plain: $0) },favorite: { model.favorite(record) },delete: { model.delete(record) }))
                                        .accessibilityElement(children: .combine)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { model.selectedID = record.id }
                                        .accessibilityAction(named: Text("Recopier")) { model.copy(record) }
                                        .accessibilityAction(named: Text(record.favorite ? "Retirer des favoris" : "Ajouter aux favoris")) { model.favorite(record) }
                                        .accessibilityAction(named: Text("Supprimer")) { model.delete(record) }
                                    Button { model.copy(record,keepWindowOpen: true) } label: {
                                        Image(systemName: "square.on.square")
                                            .font(.system(size: 12,weight: .medium))
                                            .foregroundStyle(Palette.accent)
                                            .frame(width: 29,height: 29)
                                            .background(.white.opacity(0.8),in: RoundedRectangle(cornerRadius: 7))
                                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.accent.opacity(0.18),lineWidth: 1))
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).padding(.trailing,12)
                                        .help("Copier directement sans fermer la fenêtre")
                                        .accessibilityLabel("Copier rapidement : \(record.title)")
                                }
                                .background(model.selectedID == record.id ? Palette.pale.opacity(0.65) : .white,in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedID == record.id ? Palette.accent.opacity(0.45) : Palette.line.opacity(0.6),lineWidth: 1))
                                .id(record.id)
                            }
                        }.padding(.horizontal,12).padding(.bottom,16)
                    }
                    .onChange(of: model.scrollRequest) { _,id in if let id { proxy.scrollTo(id,anchor: .center) } }
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !model.query.isEmpty { return "Aucun résultat" }
        if model.filter == .favorites { return "Gardez l’essentiel" }
        if model.filter != .all { return "Rien ici pour le moment" }
        return "Votre prochaine copie arrive ici"
    }
    private var emptySubtitle: String {
        if !model.query.isEmpty { return "Essayez un autre mot ou le nom de l’application." }
        if model.filter == .favorites { return "Ajoutez une étoile aux éléments que vous réutilisez souvent." }
        return "Copiez quelque chose avec ⌘C dans une autre application, puis revenez ici."
    }

    @ViewBuilder private var preview: some View {
        if let record = model.selected {
            VStack(alignment: .leading,spacing: 0) {
                HStack {
                    Label(record.kind.label.uppercased(),systemImage: record.kind.symbol)
                        .font(.system(size: 10,weight: .semibold)).tracking(0.8).foregroundStyle(Palette.accent)
                    Spacer()
                    Button { model.favorite() } label: { Image(systemName: record.favorite ? "star.fill" : "star").foregroundStyle(record.favorite ? Color.orange : Palette.muted) }
                        .buttonStyle(.plain).help(record.favorite ? "Retirer des favoris · ⌘D" : "Ajouter aux favoris · ⌘D")
                        .accessibilityLabel(record.favorite ? "Retirer des favoris" : "Ajouter aux favoris")
                    Button { model.delete() } label: { Image(systemName: "trash").foregroundStyle(Palette.muted) }
                        .buttonStyle(.plain).padding(.leading,12).help("Supprimer cet élément").accessibilityLabel("Supprimer cet élément")
                }.padding(.bottom,22)
                Group {
                    if record.kind == .image {
                        if let image = model.selectedImage {
                            Image(nsImage: image).resizable().scaledToFit().padding(14).frame(maxWidth: .infinity,maxHeight: .infinity)
                                .background(Palette.sidebar,in: RoundedRectangle(cornerRadius: 10))
                        } else if model.selectionLoading { ProgressView().frame(maxWidth: .infinity,maxHeight: .infinity) }
                        else { Text("Aperçu de l’image indisponible").foregroundStyle(Palette.muted).frame(maxWidth: .infinity,maxHeight: .infinity) }
                    } else if record.kind == .files {
                        ScrollView {
                            VStack(alignment: .leading,spacing: 14) {
                                ForEach(Array(model.selectedFiles.enumerated()),id: \.offset) { _,file in
                                        let url = file.url
                                        HStack(alignment: .top,spacing: 12) {
                                            Image(systemName: "doc").font(.system(size: 24)).foregroundStyle(Palette.accent)
                                            VStack(alignment: .leading,spacing: 5) {
                                                Text(url.lastPathComponent).font(.system(size: 13,weight: .medium)).textSelection(.enabled)
                                                Text(url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                                if !file.exists { Text("Fichier déplacé ou supprimé").font(.system(size: 10)).foregroundStyle(.orange) }
                                            }
                                        }.frame(maxWidth: .infinity,alignment: .leading).padding(14).background(Palette.background,in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        Text("Les fichiers restent à leur emplacement d’origine.").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top,12)
                    } else {
                        NativeTextPreview(id: record.id,text: model.selectedText,fontSize: record.kind == .link ? 16 : 14)
                            .background(Palette.background,in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line.opacity(0.65),lineWidth: 1))
                    }
                }.frame(maxWidth: .infinity,maxHeight: .infinity)
                VStack(alignment: .leading,spacing: 8) {
                    HStack(spacing: 7) {
                        AppIcon(bundle: record.sourceBundle).frame(width: 16,height: 16)
                        Text(record.sourceName).font(.system(size: 11,weight: .medium))
                        Spacer()
                        Text(record.lastCopied,format: .dateTime.day().month(.abbreviated).hour().minute()).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    HStack {
                        Text("\(record.copyCount) copie\(record.copyCount == 1 ? "" : "s")")
                        Text("·")
                        Text(record.kind == .image ? ByteCountFormatter.string(fromByteCount: Int64(record.byteCount),countStyle: .file) : model.selectedCharacterCount.map { "\($0.formatted()) caractères" } ?? "Chargement…")
                    }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.padding(.top,20).padding(.bottom,20)
                Button { model.copy() } label: {
                    HStack { Image(systemName: "square.on.square"); Text("Recopier"); Spacer(); Text("↵").foregroundStyle(.white.opacity(0.7)) }
                        .font(.system(size: 13,weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal,16).frame(height: 43).background(Palette.accent,in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityLabel("Recopier l’élément sélectionné")
                Text("Puis ⌘V dans votre application.").font(.system(size: 10)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.top,10)
            }.padding(24).background(.white)
        } else {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Palette.pale).frame(width: 86,height: 86).rotationEffect(.degrees(-7))
                    Image(systemName: "square.on.square").font(.system(size: 32,weight: .light)).foregroundStyle(Palette.accent)
                }.padding(.bottom,12)
                Text("Copiez. Retrouvez. Recollez.").font(.system(size: 21,weight: .semibold)).tracking(-0.4)
                Text("Les bonnes idées méritent\nplus qu’une seule place.").font(.system(size: 13)).lineSpacing(5).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                HStack(spacing: 5) { key("⌥"); key("W") }.padding(.top,14)
                Text("Votre historique, à portée de clavier.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity,maxHeight: .infinity).background(.white)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("Tout reste sur ce Mac",systemImage: "lock").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            Text("\(GlobalHotKey.display) pour ouvrir").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Rectangle().fill(Palette.line).frame(width: 1,height: 12)
            Button { model.showClear = true } label: { Text("Effacer l’historique").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                .buttonStyle(.plain).disabled(model.total == 0)
        }.padding(.horizontal,24).frame(height: 39).background(Palette.background).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private func key(_ text: String) -> some View {
        Text(text).font(.system(size: 12,weight: .medium)).padding(.horizontal,10).frame(height: 28).background(Palette.background,in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.line,lineWidth: 1))
    }
    private func banner(_ title: String, symbol: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center,spacing: 8) {
            Image(systemName: symbol)
            Text(title).font(.system(size: 11)).fixedSize(horizontal: false,vertical: true)
            Spacer()
            Button(button,action: action).font(.system(size: 11)).buttonStyle(.borderless)
        }.foregroundStyle(Palette.ink).padding(12).background(Color.orange.opacity(0.10))
    }
}

private struct ClipRow: View {
    let record: ClipRecord
    var body: some View {
        HStack(alignment: .top,spacing: 12) {
            Image(systemName: record.kind.symbol).font(.system(size: 15,weight: .medium)).foregroundStyle(color)
                .frame(width: 34,height: 36).background(color.opacity(0.09),in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading,spacing: 7) {
                HStack(alignment: .top,spacing: 4) {
                    Text(record.title).font(.system(size: 12,weight: .semibold)).lineLimit(2).frame(maxWidth: .infinity,alignment: .leading)
                    if record.favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                }
                if record.kind == .text && record.preview != record.title {
                    Text(record.preview.replacingOccurrences(of: "\n",with: " ")).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(record.sourceName).lineLimit(1)
                    Text("·")
                    Text(record.lastCopied,style: .time)
                    Spacer(minLength: 0)
                    if record.copyCount > 1 { Text("×\(record.copyCount)").monospacedDigit().foregroundStyle(Palette.accent) }
                }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
        }.padding(12)
    }
    private var color: Color {
        switch record.kind { case .text: return Palette.accent; case .link: return .blue; case .image: return .orange; case .files: return Palette.green }
    }
}

private struct AppIcon: View {
    let bundle: String
    var body: some View {
        if let image = AppIconCache.image(for: bundle) {
            Image(nsImage: image).resizable().scaledToFit()
        } else { Image(systemName: "app").resizable().scaledToFit().foregroundStyle(Palette.muted) }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: HistoryModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading,spacing: 22) {
            HStack {
                Text("Réglages").font(.system(size: 23,weight: .semibold))
                Spacer()
                Button("Terminé") { dismiss() }.keyboardShortcut(.escape,modifiers: [])
            }
            GroupBox {
                VStack(alignment: .leading,spacing: 15) {
                    Toggle("Ouvrir Recolle à la connexion",isOn: Binding(get: { model.loginEnabled },set: { model.toggleLogin($0) }))
                    Text("Recolle doit être ouvert pour enregistrer vos copies. Fermer sa fenêtre laisse l’enregistrement actif dans la barre de menus.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false,vertical: true)
                    Divider()
                    HStack { Text("Raccourci global"); Spacer(); Text(GlobalHotKey.display).fontWeight(.medium) }
                    if !model.shortcutAvailable { Text("Raccourci indisponible : utilisez l’icône Recolle dans la barre de menus.").font(.system(size: 11)).foregroundStyle(.orange) }
                }.padding(10)
            }
            GroupBox {
                VStack(alignment: .leading,spacing: 12) {
                    Picker("Conserver l’historique",selection: $model.retention) {
                        Text("Sans limite de durée").tag(0); Text("7 jours").tag(7); Text("30 jours").tag(30); Text("90 jours").tag(90)
                    }
                    Text("Jusqu’à 5 000 éléments et 250 Mo, puis les plus anciennes copies sont retirées. Les favoris sont conservés. Une copie peut peser jusqu’à 12 Mo.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false,vertical: true)
                }.padding(10)
            }
            GroupBox {
                VStack(alignment: .leading,spacing: 12) {
                    HStack { Text("Applications à ignorer").fontWeight(.medium); Spacer(); Button("Ajouter…",action: chooseApp) }
                    Text("Les gestionnaires de mots de passe connus et les copies signalées comme confidentielles sont exclus. Un secret copié depuis une autre application peut être enregistré : utilisez la pause si besoin.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false,vertical: true)
                    if !model.ignoredApps.isEmpty {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(model.ignoredApps,id: \.self) { id in
                                    HStack {
                                        Text(appName(id)).font(.system(size: 11)).lineLimit(1)
                                        Spacer()
                                        Button { model.removeIgnoredApp(id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Retirer \(appName(id)) des exclusions")
                                    }
                                }
                            }
                        }.frame(maxHeight: 90)
                    }
                }.padding(10)
            }
            Text("Stockage local dans Bibliothèque/Application Support/Recolle. Aucun compte ni connexion réseau. Les fichiers copiés sont des références, les textes et images sont enregistrés sur le disque de votre session Mac.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false,vertical: true)
        }.font(.system(size: 12)).padding(28).frame(width: 530).foregroundStyle(Palette.ink).background(Palette.background).preferredColorScheme(.light)
    }
    private func chooseApp() {
        let panel = NSOpenPanel(); panel.title = "Choisir une application à ignorer"
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { model.addIgnoredApp(url) }
    }
    private func appName(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
    }
}
