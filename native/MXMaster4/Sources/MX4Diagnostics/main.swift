import Foundation
import MXMaster4Core
import MXMaster4HID

@main struct Diagnostics {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let snapshot: DiagnosticSnapshot
            if args.count == 2 && args[0] == "--replay" {
                snapshot = try RecordedMouse.read(directory: URL(fileURLWithPath: args[1]))
            } else if args == ["--scan"] {
                snapshot = MouseScanner.scan()
            } else if args == ["--request-input-monitoring"] {
                print(MouseScanner.requestInputMonitoring() ? "Permission granted; restart this process." : "Permission not granted.")
                return
            } else {
                print("Usage: mx4-diagnostics --replay <specimen-directory> | --scan | --request-input-monitoring")
                if !args.isEmpty && args != ["--help"] { Foundation.exit(2) }
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            FileHandle.standardOutput.write(data)
            print()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }
}
