#if DEBUG
import AppKit
import Darwin
import PostDataKit

/// Scripted scenario for memory profiling, enabled with `-PostDataDebugMemory <url>`.
/// Logs the process footprint (what Activity Monitor shows as "Memory") after each step
/// to `<data directory>/memlog.txt`.
extension AppModel {
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    func runMemoryScript(url: String) async {
        let logURL = AppSettings.dataDirectory.appending(path: "memlog.txt")
        try? FileManager.default.removeItem(at: logURL)
        func log(_ step: String) async {
            try? await Task.sleep(for: .seconds(1.5)) // let SwiftUI render and settle
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            let line = "\(step.padding(toLength: 28, withPad: " ", startingAt: 0)) footprint \(String(format: "%6.1f", Self.footprintMB())) MB   malloc live \(String(format: "%6.1f", Double(stats.size_in_use) / 1_048_576)) MB   malloc reserved \(String(format: "%6.1f", Double(stats.size_allocated) / 1_048_576)) MB\n"
            let released = UserDefaults.standard.bool(forKey: "PostDataDebugRelief") ? malloc_zone_pressure_relief(nil, 0) : 0
            var after = malloc_statistics_t()
            malloc_zone_statistics(nil, &after)
            let reliefLine = "   after pressure relief     footprint \(String(format: "%6.1f", Self.footprintMB())) MB   (released \(String(format: "%.1f", Double(released) / 1_048_576)) MB, reserved now \(String(format: "%.1f", Double(after.size_allocated) / 1_048_576)) MB)\n"
            let combined = line + (UserDefaults.standard.bool(forKey: "PostDataDebugRelief") ? reliefLine : "")
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(combined.utf8))
                try? handle.close()
            } else {
                try? Data(combined.utf8).write(to: logURL)
            }
        }
        func sendAndWait(_ tab: RequestTabState) async {
            send(tab)
            while tab.response.isLoading { try? await Task.sleep(for: .milliseconds(50)) }
        }

        await log("idle")
        var tab = tabs.newRequest()
        tab.draft.setURL(url)
        await log("new tab")
        await sendAndWait(tab)
        await log("1st request")
        await sendAndWait(tab)
        await log("2nd request (same tab)")
        for _ in 0..<10 { await sendAndWait(tab) }
        await log("+10 requests (same tab)")
        for index in 0..<10 {
            tab = tabs.newRequest()
            tab.draft.setURL(url)
            await sendAndWait(tab)
            if index == 0 { await log("2nd tab + request") }
        }
        await log("11 tabs, each sent")
        for _ in 0..<3 {
            for state in tabs.tabs.compactMap(\.requestState) {
                tabs.selectedTabID = state.id
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        await log("cycled through tabs x3")
        for id in tabs.tabs.map(\.id) { tabs.close(id) }
        await log("closed all tabs")
        try? await Task.sleep(for: .seconds(3))
        await log("idle after close")
        try? Data("DONE\n".utf8).write(to: AppSettings.dataDirectory.appending(path: "memlog.done"))
    }
}
#endif
