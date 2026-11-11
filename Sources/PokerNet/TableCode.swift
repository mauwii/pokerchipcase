/// 4-digit table code; the TLS key is derived from it.
public struct TableCode: Hashable, Codable, Sendable {
    public let digits: String

    public init?(_ digits: String) {
        guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.digits = digits
    }

    public static func random() -> TableCode {
        TableCode(String(format: "%04d", Int.random(in: 0...9999)))!
    }
}
