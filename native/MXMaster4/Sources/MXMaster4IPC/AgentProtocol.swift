import Foundation
import Security

@objc public protocol MX4AgentProtocol {
    func snapshot(reply: @escaping @Sendable (Data?, String?) -> Void)
    func requestInputMonitoring(reply: @escaping @Sendable (Data?, String?) -> Void)
}

public enum AgentIdentity {
    public static let plistName = "MXMaster4Agent.plist"
    public static let relativeBundle = "Contents/Library/LoginItems/MXMaster4Agent.app"

    public static func serviceName(in bundle: Bundle = .main) throws -> String {
        guard let name = bundle.object(forInfoDictionaryKey: "MX4ServiceName") as? String, !name.isEmpty else {
            throw IdentityError(message: "The application has no agent service name. Rebuild the Xcode project.")
        }
        return name
    }

    /// Pin the embedded peer's designated requirement; a matching bundle ID alone is insufficient.
    public static func requirement(for url: URL) throws -> String {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        let flags = SecCSFlags(rawValue: 0)
        try check(SecStaticCodeCreateWithPath(url as CFURL, flags, &code))
        guard let code else { throw IdentityError(message: "Cannot inspect the peer application.") }
        try check(SecStaticCodeCheckValidity(code, flags, nil))
        try check(SecCodeCopyDesignatedRequirement(code, flags, &requirement))
        guard let requirement else { throw IdentityError(message: "The peer application has no code signature.") }
        try check(SecRequirementCopyString(requirement, flags, &text))
        guard let text else { throw IdentityError(message: "Cannot read the peer's signing requirement.") }
        return text as String
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw IdentityError(message: (SecCopyErrorMessageString(status, nil) as String?) ?? "Code-signing error \(status)")
        }
    }
}

public struct IdentityError: LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
