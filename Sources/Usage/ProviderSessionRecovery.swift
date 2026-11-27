import CFNetwork
import Foundation
import Darwin

enum ProviderSessionRecovery {
    static func fetch(
        operation: () async throws -> ConnectedUsage,
        renew: () async throws -> Void
    ) async throws -> ConnectedUsage {
        do {
            return try await operation()
        } catch ProviderConnectionError.expired {
            // The official CLI owns refresh-token rotation and persistence.
        } catch ProviderConnectionError.http(401) {
        }
        try Task.checkCancellation()
        try await renew()
        try Task.checkCancellation()
        return try await operation()
    }

    static func binary(_ command: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin/\(command)", "\(home)/.grok/bin/\(command)",
                     "/opt/homebrew/bin/\(command)", "/usr/local/bin/\(command)"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/\(command)" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func proxyEnvironment(
        _ environment: [String: String], proxies: [[String: Any]]
    ) -> [String: String] {
        guard environment["HTTPS_PROXY"] == nil, environment["https_proxy"] == nil,
              let proxy = proxies.first,
              let type = proxy[kCFProxyTypeKey as String] as? String,
              type == kCFProxyTypeHTTPS as String || type == kCFProxyTypeHTTP as String,
              let host = proxy[kCFProxyHostNameKey as String] as? String,
              !host.isEmpty,
              let port = proxy[kCFProxyPortNumberKey as String] as? Int,
              (1...65535).contains(port) else { return environment }

        // macOS labels the proxy by the destination protocol. The proxy uses HTTP CONNECT.
        var url = URLComponents()
        url.scheme = "http"
        url.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        url.port = port
        guard let address = url.url else { return environment }
        var result = environment
        result["HTTPS_PROXY"] = address.absoluteString
        return result
    }

    static func renew(_ command: String) async throws {
        guard let executable = binary(command) else { throw ProviderConnectionError.expired }
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["models"]
        if command == "agy",
           let url = URL(string: "https://oauth2.googleapis.com/token"),
           let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
           let proxies = CFNetworkCopyProxiesForURL(url as CFURL, settings)
               .takeRetainedValue() as? [[String: Any]] {
            process.environment = proxyEnvironment(ProcessInfo.processInfo.environment, proxies: proxies)
        }
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let deadline = Date().addingTimeInterval(25)
        while process.isRunning {
            guard Date() < deadline else { throw ProviderConnectionError.unavailable }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw ProviderConnectionError.unavailable }
    }
}
