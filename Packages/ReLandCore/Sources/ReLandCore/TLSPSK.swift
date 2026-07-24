import Foundation
import Network
import Security

public enum TLSPSK {
    public static func clientParameters(
        credential: PSKCredential
    ) -> NWParameters {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_add_pre_shared_key(
            options.securityProtocolOptions,
            dispatchData(credential.key),
            dispatchData(Data(credential.id.utf8))
        )

        let parameters = NWParameters(tls: options)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        return parameters
    }

    public static func serverParameters(
        credentials: [PSKCredential]
    ) throws -> NWParameters {
        guard !credentials.isEmpty else {
            throw ReLandSecurityError.invalidCredential
        }

        let options = NWProtocolTLS.Options()
        for credential in credentials {
            sec_protocol_options_add_pre_shared_key(
                options.securityProtocolOptions,
                dispatchData(credential.key),
                dispatchData(Data(credential.id.utf8))
            )
        }

        let parameters = NWParameters(tls: options)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func dispatchData(_ data: Data) -> dispatch_data_t {
        data.withUnsafeBytes { bytes in
            DispatchData(bytes: bytes) as dispatch_data_t
        }
    }
}

