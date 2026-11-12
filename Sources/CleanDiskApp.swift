import SwiftUI

@main
struct CleanDiskApp: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.runAndExit()
        }
        if CommandLine.arguments.contains("--bench-delete") {
            SelfTest.runDeleteBench()
        }
        if CommandLine.arguments.contains("--scan") {
            SelfTest.runScan()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview") {
            let outPath = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : nil
            SelfTest.runPreview(outPath: outPath)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 920, height: 760)
    }
}
