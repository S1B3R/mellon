import SwiftUI

@main
struct MellonMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.isConnected ? "sparkle" : "sparkles")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Window("Parear iPhone", id: PairingView.windowID) {
            PairingView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
