import AppKit

// Opt-in developer measurement. Logs timings only, never clipboard contents.
enum InteractionTrace {
    private static let output: URL? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--interaction-log"), args.indices.contains(index+1) else { return nil }
        return URL(fileURLWithPath: args[index+1])
    }()
    private static let queue = DispatchQueue(label: "fr.isaac.recolle.timings")
    private static var clickTime: TimeInterval = 0
    private static var monitor: Any?
    static func install() {
        guard output != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in clickTime = event.timestamp; return event }
    }
    static func selection() {
        guard let output, clickTime > 0 else { return }
        let ms = (ProcessInfo.processInfo.systemUptime-clickTime)*1000
        let data = Data("selection_ms=\(String(format: "%.3f",ms))\n".utf8)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: output) {
                _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close()
            } else { try? data.write(to: output) }
        }
    }
}
