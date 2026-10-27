import SwiftUI

@main struct MXMaster4App: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("MX Master 4") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 650)
                .task {
                    model.updateStatus()
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "--replay"), args.indices.contains(i + 1) {
                        await model.replay(URL(fileURLWithPath: args[i + 1]))
                    }
                }
                .onChange(of: scenePhase) { if $0 == .active { model.updateStatus() } }
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Hardware Recording…") { model.chooseRecording() }
                    .keyboardShortcut("o").disabled(model.busy)
                Button("Refresh from Agent") { Task { await model.refresh() } }
                    .keyboardShortcut("r").disabled(model.busy || !model.registered)
            }
        }
    }
}
