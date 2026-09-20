import Foundation
import MacBridgeCore
import MacBridgeNative

/// Read-only empirical probe. Uses the same native execution boundary as the app.
/// Prints only conformance evidence, never app names, media contents or credentials.
@main struct NativeStateProbe {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw ContractError(code: "schema_argument_required") }
            let validator = try ContractValidator(schema: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let data = try await ActionExecutor().executeGuarded(action: "get_state", params: .object([:]), shortcuts: [])
            try validator.validate("State", data)
            let report: JSON = .object(["native_get_state": .string("passed"), "contract_valid": .bool(true),
                                       "screen_locked": data["screen_locked"]!,
                                       "battery_available": .bool(data["battery"]?.object != nil),
                                       "app_count": .number(Double(data["running_apps"]?.array?.count ?? 0))])
            print(String(decoding: try report.data(), as: UTF8.self))
        } catch {
            let code = (error as? ContractError)?.code ?? "probe_failed"
            FileHandle.standardError.write(Data((code + "\n").utf8))
            exit(1)
        }
    }
}
