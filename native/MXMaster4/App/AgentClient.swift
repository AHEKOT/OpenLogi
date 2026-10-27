import Foundation
import MXMaster4Core
import MXMaster4IPC

/// One request owns its connection, deadline and continuation, all on the main actor.
@MainActor final class AgentClient {
    private var continuation: CheckedContinuation<DiagnosticSnapshot, any Error>?
    private var connection: NSXPCConnection?
    private var deadline: Task<Void, Never>?

    func snapshot(requestPermission: Bool = false) async throws -> DiagnosticSnapshot {
        let peer = Bundle.main.bundleURL.appendingPathComponent(AgentIdentity.relativeBundle)
        let requirement = try AgentIdentity.requirement(for: peer)
        let connection = NSXPCConnection(machServiceName: try AgentIdentity.serviceName())
        connection.remoteObjectInterface = NSXPCInterface(with: MX4AgentProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        self.connection = connection
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let failure: @Sendable (String) -> Void = { message in
                Task { @MainActor in self.finish(.failure(IdentityError(message: message))) }
            }
            connection.interruptionHandler = { failure("The agent stopped. Restart it and refresh.") }
            connection.invalidationHandler = { failure("Cannot connect to the agent. Check its registration and signature.") }
            connection.resume()
            deadline = Task {
                do { try await Task.sleep(for: .seconds(requestPermission ? 60 : 30)) }
                catch { return }
                finish(.failure(IdentityError(message: "The agent did not answer in time. Finish any permission dialog, then restart it.")))
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ failure($0.localizedDescription) }) as? any MX4AgentProtocol else {
                finish(.failure(IdentityError(message: "Invalid agent interface."))); return
            }
            let reply: @Sendable (Data?, String?) -> Void = { data, error in
                Task { @MainActor in
                    do {
                        if let error { throw IdentityError(message: error) }
                        guard let data else { throw IdentityError(message: "The agent returned no snapshot.") }
                        self.finish(.success(try DiagnosticSnapshot.decode(data)))
                    } catch { self.finish(.failure(error)) }
                }
            }
            if requestPermission { proxy.requestInputMonitoring(reply: reply) }
            else { proxy.snapshot(reply: reply) }
        }
    }

    private func finish(_ result: Result<DiagnosticSnapshot, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        connection?.invalidationHandler = nil; connection?.interruptionHandler = nil
        connection?.invalidate(); connection = nil
        continuation.resume(with: result)
    }
}
