import SwiftUI
import AVFoundation

@main
struct PitwallApp: App {
    @State private var model = AppModel()

    init() {
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        WindowGroup("Speler", id: "player", for: PlaybackRequest.self) { $request in
            if let request {
                PlayerScreen(request: request)
                    .environment(model)
                    .frame(minWidth: 640, minHeight: 400)
            }
        }
        .defaultSize(width: 1280, height: 760)

        Settings {
            SettingsScreen()
                .environment(model)
                .frame(width: 560, height: 620)
        }
        #else
        WindowGroup {
            RootView()
                .environment(model)
        }
        #endif
    }
}
