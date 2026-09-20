import Foundation
import Network
import CryptoKit
import MacBridgeCore

/// Small, one-request-per-connection local API. Never binds a LAN interface.
public final class LocalHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacBridge.LocalHTTP")
    private let listener: NWListener
    private let tokenHash: SHA256.Digest
    private let handler: @Sendable (JSON) async -> (Int, JSON)
    public let port: UInt16
    public init(port: UInt16, token: String, handler: @escaping @Sendable (JSON) async -> (Int, JSON)) throws {
        self.port = port; self.handler = handler; tokenHash = SHA256.hash(data: Data(token.utf8))
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
            self.queue.asyncAfter(deadline: .now() + 20) { connection.cancel() }
        }
    }
    public func start() { listener.start(queue: queue) }
    public func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = accumulated; if let data { buffer.append(data) }
            guard buffer.count <= 65536 else { self.error(connection, 413, "request_too_large"); return }
            guard error == nil else { connection.cancel(); return }
            guard let split = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete { connection.cancel() } else { self.receive(connection, accumulated: buffer) }; return
            }
            guard let text = String(data: buffer[..<split.lowerBound], encoding: .utf8) else { self.error(connection, 400, "invalid_request"); return }
            let lines = text.components(separatedBy: "\r\n")
            guard lines.first == "POST /v1/commands HTTP/1.1" else { self.error(connection, 404, "route_not_found"); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { self.error(connection, 400, "invalid_request"); return }
                let key = pair[0].lowercased()
                guard headers[key] == nil else { self.error(connection, 400, "invalid_request"); return }
                headers[key] = pair[1].trimmingCharacters(in: .whitespaces)
            }
            // Prevent browser drive-by requests and ambiguous HTTP framing.
            guard headers["origin"] == nil, headers["transfer-encoding"] == nil,
                  headers["host"] == "127.0.0.1:\(self.port)",
                  headers["content-type"]?.lowercased() == "application/json",
                  let length = headers["content-length"].flatMap(Int.init), length >= 0, length <= 60000 else {
                self.error(connection, 400, "invalid_request"); return
            }
            guard let authorization = headers["authorization"], authorization.hasPrefix("Bearer ") else { self.error(connection, 401, "unauthorized"); return }
            let supplied = SHA256.hash(data: Data(authorization.dropFirst(7).utf8))
            let difference = zip(supplied, self.tokenHash).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
            guard difference == 0 else { self.error(connection, 401, "unauthorized"); return }
            let body = buffer[split.upperBound...]
            if body.count < length {
                if complete { self.error(connection, 400, "invalid_request") } else { self.receive(connection, accumulated: buffer) }; return
            }
            guard body.count == length, let value = try? JSON.parse(Data(body)) else { self.error(connection, 400, "invalid_request"); return }
            Task {
                let (status, result) = await self.handler(value)
                self.respond(connection, status, result)
            }
        }
    }
    private func error(_ c: NWConnection, _ status: Int, _ code: String) {
        respond(c, status, .object(["error": .object(["code": .string(code), "message": .string(code.replacingOccurrences(of: "_", with: " "))])]))
    }
    private func respond(_ c: NWConnection, _ status: Int, _ value: JSON) {
        guard let body = try? value.data() else { c.cancel(); return }
        var output = Data("HTTP/1.1 \(status) Response\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        output.append(body)
        c.send(content: output, completion: .contentProcessed { _ in c.cancel() })
    }
}
