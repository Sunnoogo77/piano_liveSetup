import SwiftUI
import AppKit

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: RigModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }
}

@main
struct PianoLiveSetupApp: App {
    @StateObject private var model = RigModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Piano Live Setup") {
            Group {
                if model.ready {
                    NavigationSplitView {
                        SidebarView(m: model)
                            .navigationSplitViewColumnWidth(min: 230, ideal: 262, max: 320)
                    } detail: {
                        StageView(m: model)
                    }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    BootView(m: model)
                }
            }
            .frame(minWidth: 1020, minHeight: 700)
            .preferredColorScheme(.dark)
            .onAppear {
                delegate.model = model
                NSApp.activate(ignoringOtherApps: true)
                model.boot()
                installKeys()
            }
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }

    private func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // On laisse le champ de recherche se comporter normalement.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            // ⌘1…⌘6 : changer d'écran
            if event.modifierFlags.contains(.command),
               let d = Int(event.charactersIgnoringModifiers ?? ""), (1...Tab.allCases.count).contains(d) {
                model.tab = Tab.allCases[d - 1]
                return nil
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 123: model.nudgeTranspose(-1); return nil     // ←
            case 124: model.nudgeTranspose(1);  return nil     // →
            case 126: model.step(-1); return nil               // ↑
            case 125: model.step(1);  return nil               // ↓
            default: break
            }
            switch (event.charactersIgnoringModifiers ?? "").lowercased() {
            case "0": model.resetPitch(); return nil
            case "r": model.toggleRecording(); return nil
            case "-", "_": model.nudgeTranspose(-1); return nil
            case "+", "=": model.nudgeTranspose(1); return nil
            case "[": model.nudgeOctave(-1); return nil
            case "]": model.nudgeOctave(1); return nil
            case "p", " ": model.panic(); return nil
            case "l": model.toggleLocal(); return nil
            default: return event
            }
        }
    }
}
