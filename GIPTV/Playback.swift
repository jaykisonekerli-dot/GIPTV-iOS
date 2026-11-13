import SwiftUI
import AVKit
import AVFoundation

@MainActor final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    let media: Media
    private weak var model: AppModel?
    @Published var message = "Abrindo vídeo…"
    @Published var paused = false
    private var token: Any?
    private var completed: NSObjectProtocol?
    private var observation: NSKeyValueObservation?
    private var ready = false
    private var stopped = false
    private var retries = 0
    private var retryTask: Task<Void, Never>?
    init(media: Media, model: AppModel) {
        self.media = media; self.model = model
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.automaticallyWaitsToMinimizeStalling = true
        token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.save() }
        }
        load()
    }
    func load() {
        guard !stopped, let model else { return }
        ready = false; message = "Abrindo vídeo…"
        observation?.invalidate()
        if let completed { NotificationCenter.default.removeObserver(completed) }; completed = nil
        do {
            let item = AVPlayerItem(url: try model.api.stream(media))
            item.preferredForwardBufferDuration = 10
            player.replaceCurrentItem(with: item)
            observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, !self.stopped, self.player.currentItem === item else { return }
                    if item.status == .readyToPlay {
                        self.message = ""
                        let saved = self.media.kind == .live ? 0 : model.data.progress[self.media.id] ?? 0
                        let duration = item.duration.seconds
                        if saved > 0 && (!duration.isFinite || saved < duration - 1) {
                            self.player.seek(to: CMTime(seconds: saved, preferredTimescale: 600)) { [weak self] _ in
                                Task { @MainActor in guard let self, !self.stopped else { return }; self.ready = true; if !self.paused { self.player.play() } }
                            }
                        } else { self.ready = true; if !self.paused { self.player.play() } }
                    } else if item.status == .failed {
                        self.ready = false
                        if self.retries < 3 {
                            self.retries += 1; self.message = "Reconectando (\(self.retries)/3)…"
                            self.retryTask?.cancel()
                            self.retryTask = Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                guard !Task.isCancelled else { return }; self?.load()
                            }
                        } else { self.message = "Não foi possível reproduzir. Confira o serviço e se o formato é compatível com o iPhone." }
                    }
                }
            }
            completed = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.model?.save(self.media, position: 0, duration: 0, ended: true); self.ready = false; self.paused = true; self.message = "Reprodução concluída" }
            }
        } catch { message = "Endereço de reprodução inválido." }
    }
    func save() {
        guard ready else { return }
        model?.save(media, position: player.currentTime().seconds, duration: player.currentItem?.duration.seconds ?? 0)
    }
    func toggle() {
        if player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate { save(); player.pause(); paused = true }
        else { paused = false; player.play() }
    }
    func background() { save(); paused = true; player.pause(); retryTask?.cancel() }
    func restart() {
        model?.data.progress.removeValue(forKey: media.id); model?.persist()
        player.seek(to: .zero); paused = false; ready = true; player.play()
    }
    func stop() {
        guard !stopped else { return }; save(); stopped = true; retryTask?.cancel(); player.pause()
        if let token { player.removeTimeObserver(token) }; token = nil
        if let completed { NotificationCenter.default.removeObserver(completed) }; completed = nil
        observation?.invalidate(); observation = nil
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
@MainActor struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController(); c.player = player; c.showsPlaybackControls = true
        c.videoGravity = .resizeAspect; c.allowsPictureInPicturePlayback = true
        return c
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
}
@MainActor struct PlaybackView: View {
    let media: Media
    @ObservedObject var model: AppModel
    @StateObject private var controller: PlaybackController
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.dismiss) var dismiss
    @State private var chrome = true
    @State private var timerID = UUID()
    @State private var guide: [String] = []
    @State private var showGuide = false
    init(media: Media, model: AppModel) {
        self.media = media; self.model = model
        _controller = StateObject(wrappedValue: PlaybackController(media: media, model: model))
    }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            NativePlayer(player: controller.player).ignoresSafeArea()
                .simultaneousGesture(TapGesture().onEnded { chrome = true; timerID = UUID() })
            if chrome {
                VStack {
                    HStack {
                        Button { controller.stop(); dismiss() } label: { Label("Voltar", systemImage: "chevron.left") }
                        Spacer()
                        Button(controller.paused ? "Continuar" : "Pausar") { controller.toggle(); timerID = UUID() }
                    }
                    Text(media.title).font(.caption).lineLimit(2)
                    if !controller.message.isEmpty { Text(controller.message).font(.caption) }
                    HStack {
                        if media.kind != .live { Button("Do início") { controller.restart() } }
                        Button("Informações") { showGuide = true }
                    }.font(.caption)
                }.padding().background(.black.opacity(0.72))
            }
        }.statusBarHidden(!chrome)
            .task(id: timerID) { try? await Task.sleep(nanoseconds: 4_000_000_000); if !Task.isCancelled && controller.player.timeControlStatus == .playing { chrome = false } }
            .onDisappear { controller.stop() }
            .onChange(of: scenePhase) { phase in if phase != .active { controller.background(); chrome = true } }
            .sheet(isPresented: $showGuide) {
                NavigationStack {
                    List {
                        if media.kind == .live { ForEach(guide, id: \.self) { Text($0) }; if guide.isEmpty { Text("Programação não disponibilizada no momento.") } }
                        else { Text(media.summary.isEmpty ? "O serviço não disponibilizou um resumo." : media.summary) }
                    }.navigationTitle(media.kind == .live ? "Programação" : "Resumo")
                        .toolbar { Button("Fechar") { showGuide = false } }
                        .task { if media.kind == .live { guide = (try? await model.api.guide(media)) ?? [] } }
                }
            }
    }
}
