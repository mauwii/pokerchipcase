import CryptoKit
import Foundation
import Network

/// TLS 1.2 with a pre-shared key derived from the table code, see docs/PROTOCOL.md.
enum PSK {
    static let identity = "pokerchipcase"

    static func key(for code: TableCode) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.digits.utf8)),
            salt: Data("pokerchipcase-v1".utf8),
            info: Data("pokerchipcase-psk".utf8),
            outputByteCount: 32
        )
    }

    /// TCP + TLS-PSK, also peer-to-peer (AWDL).
    static func parameters(code: TableCode) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        let key = key(for: code).withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(sec, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(sec, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        // Notice a vanished peer (phone left Wi-Fi, battery died) within seconds, not minutes.
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionDropTime = 10

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        return parameters
    }
}
