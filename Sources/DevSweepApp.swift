import SwiftUI

@main
struct DevSweepApp: App {
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
        if CommandLine.arguments.contains("--audit") {
            SelfTest.runAudit()
        }
        if CommandLine.arguments.contains("--tools-md") {
            SelfTest.runTools(asMarkdown: true)
        }
        if CommandLine.arguments.contains("--tools") {
            SelfTest.runTools(asMarkdown: false)
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
        .defaultSize(width: 1040, height: 860)
    }
}
