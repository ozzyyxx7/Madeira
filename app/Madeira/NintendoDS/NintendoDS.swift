import Foundation
import SwiftUI
import UniformTypeIdentifiers

private enum DSFiles {
    static let root = URL.documentsDirectory.appending(path: "Nintendo DS", directoryHint: .isDirectory)
    static let games = root.appending(path: "Games", directoryHint: .isDirectory)
    static let saves = root.appending(path: "Saves", directoryHint: .isDirectory)
    static let system = root.appending(path: "System", directoryHint: .isDirectory)

    static func createDirectories() throws {
        for folder in [games, saves, system] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}

private struct DSGame: Identifiable, Hashable {
    let url: URL
    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor private final class DSLibraryModel: ObservableObject {
    @Published private(set) var games: [DSGame] = []
    @Published var error: String?

    func reload() {
        do {
            try DSFiles.createDirectories()
            games = try FileManager.default.contentsOfDirectory(
                at: DSFiles.games, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "nds" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .map(DSGame.init(url:))
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }

    func importROM(_ source: URL) {
        guard source.pathExtension.lowercased() == "nds" else {
            error = "Select a Nintendo DS .nds file."
            return
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try DSFiles.createDirectories()
            let base = source.deletingPathExtension().lastPathComponent
            var target = DSFiles.games.appending(path: source.lastPathComponent)
            var duplicate = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = DSFiles.games.appending(path: "\(base) (\(duplicate)).nds")
                duplicate += 1
            }
            try FileManager.default.copyItem(at: source, to: target)
            reload()
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ game: DSGame) {
        do {
            try FileManager.default.removeItem(at: game.url)
            reload() // Keep battery saves if the game is imported again.
        } catch { self.error = error.localizedDescription }
    }
}

struct NintendoDSLibraryView: View {
    let search: String
    @StateObject private var model = DSLibraryModel()
    @State private var importing = false
    @State private var selected: DSGame?

    private var visible: [DSGame] {
        search.isEmpty ? model.games : model.games.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image("DSDualScreen").renderingMode(.template)
                        .font(.system(size: 30))
                        .frame(width: 46, height: 54)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nintendo DS").font(.headline)
                        Text("Play .nds games with melonDS DS. ROMs and saves stay on this device.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            Section("Games") {
                if visible.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No DS games yet" : "No matching DS games",
                                           systemImage: "square.stack.3d.up",
                                           description: Text(search.isEmpty ? "Import a .nds file to play." : "Try a different search."))
                } else {
                    ForEach(visible) { game in
                        Button { selected = game } label: {
                            HStack(spacing: 14) {
                                Image("DSDualScreen").renderingMode(.template)
                                    .frame(width: 28, height: 32)
                                    .foregroundStyle(.tint)
                                Text(game.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "play.fill").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { model.remove(game) }
                        }
                    }
                }
            }
            Section {
                Button { importing = true } label: {
                    Label("Import .nds game", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("You can also copy .nds files to Madeira Dev → Nintendo DS → Games in Files. Battery saves are stored in the Saves folder.")
            }
        }
        .onAppear { model.reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "nds") ?? .data]) { result in
            switch result {
            case .success(let url): model.importROM(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .fullScreenCover(item: $selected) { game in NintendoDSPlayView(game: game) }
        .alert("Nintendo DS", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private final class DSVideoModel: ObservableObject {
    @Published var image: UIImage?
    var size = CGSize(width: 256, height: 384)
}

private struct DSDisplaySurface: View {
    let session: DSGameSession
    @ObservedObject var video: DSVideoModel

    private func updateTouch(_ point: CGPoint, in bounds: CGSize) {
        guard video.size.width > 0, video.size.height > 0 else { return }
        let scale = min(bounds.width / video.size.width, bounds.height / video.size.height)
        let size = CGSize(width: video.size.width * scale, height: video.size.height * scale)
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        guard rect.contains(point), rect.width > 0, rect.height > 0 else {
            session.setTouch(x: 0, y: 0, pressed: false)
            return
        }
        let x = Int16(clamping: Int((point.x - rect.minX) / rect.width * 65535 - 32768))
        let y = Int16(clamping: Int((point.y - rect.minY) / rect.height * 65535 - 32768))
        session.setTouch(x: x, y: y, pressed: true)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = video.image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { updateTouch($0.location, in: geometry.size) }
                .onEnded { _ in session.setTouch(x: 0, y: 0, pressed: false) })
        }
    }
}

private final class DSGameSession: NSObject, ObservableObject, DSCoreBridgeDelegate {
    @Published var error: String?
    @Published var running = false
    let core = DSCoreBridge()
    let video = DSVideoModel()
    private var frames = 0

    func start(_ game: DSGame) {
        guard !running else { return }
        do {
            try DSFiles.createDirectories()
            core.delegate = self
            try core.startROM(at: game.url, systemURL: DSFiles.system, save: DSFiles.saves)
            running = core.isRunning
        } catch { self.error = error.localizedDescription }
    }

    func stop() { core.stop(); running = false; video.image = nil }
    func setButton(_ id: Int, pressed: Bool) { core.setButton(UInt(id), pressed: pressed) }
    func setTouch(x: Int16, y: Int16, pressed: Bool) { core.setTouchX(x, y: y, pressed: pressed) }

    func dsCore(_ core: DSCoreBridge, didRenderImage image: UIImage) {
        frames += 1
        if frames <= 3 || frames % 120 == 0 {
            core.recordDiagnostic("frame=\(frames) image=\(image.size)")
        }
        video.size = core.videoSize
        video.image = image
    }
}

private func dsDisplaySize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
    let height = max(1, min(maxHeight, maxWidth * 1.5))
    return CGSize(width: height * 2.0 / 3.0, height: height)
}

private struct DSControl: View {
    let title: String
    let id: Int
    let session: DSGameSession
    @State private var held = false

    var body: some View {
        Text(title)
            .font(.system(size: title.count > 2 ? 11 : 18, weight: .bold, design: .rounded))
            .frame(width: title.count > 2 ? 65 : 52, height: 52)
            .background(held ? Color.accentColor : Color.white.opacity(0.20), in: Circle())
            .foregroundStyle(.white)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !held { held = true; session.setButton(id, pressed: true) } }
                .onEnded { _ in held = false; session.setButton(id, pressed: false) })
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
}

private struct DSDPad: View {
    let session: DSGameSession
    var body: some View {
        VStack(spacing: 0) {
            DSControl(title: "▲", id: 4, session: session)
            HStack(spacing: 0) {
                DSControl(title: "◀", id: 6, session: session)
                Color.clear.frame(width: 52, height: 52)
                DSControl(title: "▶", id: 7, session: session)
            }
            DSControl(title: "▼", id: 5, session: session)
        }
    }
}

private struct DSFaceButtons: View {
    let session: DSGameSession
    var body: some View {
        VStack(spacing: 0) {
            DSControl(title: "X", id: 9, session: session)
            HStack(spacing: 52) {
                DSControl(title: "Y", id: 1, session: session)
                DSControl(title: "A", id: 8, session: session)
            }
            DSControl(title: "B", id: 0, session: session)
        }
    }
}

private struct NintendoDSPlayView: View {
    let game: DSGame
    @StateObject private var session = DSGameSession()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                HStack {
                    Button { session.stop(); dismiss() } label: { Label("Done", systemImage: "xmark.circle.fill") }
                    Spacer()
                    Text(game.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text("melonDS DS").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.top, 8)

                if geometry.size.width > geometry.size.height {
                    let screen = dsDisplaySize(maxWidth: geometry.size.width - 352,
                                               maxHeight: geometry.size.height - 60)
                    HStack(spacing: 16) {
                        VStack(spacing: 16) {
                            DSControl(title: "L", id: 10, session: session)
                            DSDPad(session: session)
                            DSControl(title: "SELECT", id: 2, session: session)
                        }.frame(width: 160)
                        DSDisplaySurface(session: session, video: session.video)
                            .frame(width: screen.width, height: screen.height)
                        VStack(spacing: 16) {
                            DSControl(title: "R", id: 11, session: session)
                            DSFaceButtons(session: session)
                            DSControl(title: "START", id: 3, session: session)
                        }.frame(width: 160)
                    }
                } else {
                    let screen = dsDisplaySize(maxWidth: geometry.size.width - 16,
                                               maxHeight: geometry.size.height - 310)
                    DSDisplaySurface(session: session, video: session.video)
                        .frame(width: screen.width, height: screen.height)
                    HStack(alignment: .center, spacing: 4) {
                        DSDPad(session: session)
                        Spacer(minLength: 0)
                        DSFaceButtons(session: session)
                    }.padding(.horizontal, 8)
                    HStack(spacing: 20) {
                        DSControl(title: "L", id: 10, session: session)
                        DSControl(title: "SELECT", id: 2, session: session)
                        DSControl(title: "START", id: 3, session: session)
                        DSControl(title: "R", id: 11, session: session)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .statusBarHidden()
        .onAppear { session.start(game) }
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { _, phase in
            session.core.setPaused(phase != .active)
        }
        .alert("Nintendo DS", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("Close") { session.stop(); dismiss() }
        } message: { Text(session.error ?? "") }
    }
}
