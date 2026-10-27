import AppKit
import MXMaster4Core
import MXMaster4HID
import MXMaster4IPC
import OSLog

final class AgentService: NSObject, MX4AgentProtocol, NSXPCListenerDelegate {
    private let io = DispatchQueue(label: "dev.openlogi.mx4.hid")

    func snapshot(reply: @escaping @Sendable (Data?, String?) -> Void) {
        io.async { Self.send(MouseScanner.scan(), reply: reply) }
    }

    func requestInputMonitoring(reply: @escaping @Sendable (Data?, String?) -> Void) {
        io.async {
            let granted = MouseScanner.requestInputMonitoring()
            Self.send(DiagnosticSnapshot(recorded: false, inputMonitoringGranted: granted, mice: [],
                issues: ["After changing Input Monitoring, restart the agent and refresh."]), reply: reply)
        }
    }

    private static func send(_ value: DiagnosticSnapshot, reply: @Sendable (Data?, String?) -> Void) {
        do { reply(try JSONEncoder().encode(value), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid() else { return false }
        connection.exportedInterface = NSXPCInterface(with: MX4AgentProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

do {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let service = AgentService()
    let listener = NSXPCListener(machServiceName: try AgentIdentity.serviceName())
    var parent = Bundle.main.bundleURL
    for _ in 0..<4 { parent.deleteLastPathComponent() }
    listener.setConnectionCodeSigningRequirement(try AgentIdentity.requirement(for: parent))
    listener.delegate = service
    listener.resume()
    withExtendedLifetime((listener, service)) { app.run() }
} catch {
    Logger(subsystem: "dev.openlogi.mxmaster4", category: "agent").fault("Agent startup failed: \(error.localizedDescription, privacy: .public)")
    exit(1)
}
