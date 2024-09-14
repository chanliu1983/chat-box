import Foundation
import Network
import Compression
import Combine

class ServerCommunicator: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false

    private var connection: NWConnection?

    init() {}

    func startConnection(host: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        let ip4 = IPv4Address(host)!

        let host = NWEndpoint.Host.ipv4(ip4)
        let port = NWEndpoint.Port(rawValue: port)

        if let port = port {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { sec_protocol_metadata, sec_trust, sec_protocol_verify_complete in
                // Accept self-signed certificates
                sec_protocol_verify_complete(true)
            }, DispatchQueue.global())
            let parameters = NWParameters(tls: tlsOptions)

            connection = NWConnection(host: host, port: port, using: parameters)

            connection?.stateUpdateHandler = { [weak self] newState in
                DispatchQueue.main.async {
                    switch newState {
                    case .ready:
                        self?.isConnected = true
                        self?.isConnecting = false
                        completion(true)
                    case .failed(_), .cancelled:
                        self?.isConnected = false
                        self?.isConnecting = false
                        completion(false)
                    default:
                        break
                    }
                }
            }

            connection?.start(queue: .global())
        }
    }

    func stopConnection() {
        connection?.cancel()
        isConnected = false
        isConnecting = false
    }

    func joinConduit(conduit : String, isConnect: Bool) {
        guard let connection = connection, isConnected else {
            return
        }

        let payloadData: [String: Any] = [
            "message": conduit,
            "action": isConnect ? "connect" : "disconnect",
            "timestamp": "\(Date())"
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: connection, textData: payload) { success in
            if success {
                print("Joined conduit")
            } else {
                print("Failed to join conduit")
            }
        }
    }

    func sendMessage(message: String, conduit: String, completion: @escaping (Bool) -> Void) {
        guard let connection = connection, isConnected else {
            completion(false)
            return
        }

        let payloadData: [String: Any] = [
            "message": message,
            "action": "send",
            "timestamp": "\(Date())",
            "target": conduit
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: connection, textData: payload, completion: completion)
    }

    func stormConduit(conduit: String, count: Int, message: String) {
        guard let connection = connection, isConnected else {
            return
        }
        
        let payloadData: [String: Any] = [
                "message": "Storm \(count) : \(message)",
                "action": "send",
                "timestamp": "\(Date())",
                "target": conduit
            ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: self.connection!, textData: payload) { success in
            if success {
                print("Storm message sent")
            } else {
                print("Failed to send storm message")
            }
        }
    }

    func storeConduit(conduit: String, message: String, key: String) {
        guard let connection = connection, isConnected else {
            return
        }

        let payloadData: [String: Any] = [
            "message": message,
            "action": "store",
            "timestamp": "\(Date())",
            "target": conduit,
            "key": key
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: connection, textData: payload) { success in
            if success {
                print("Key-value stored")
            } else {
                print("Failed to store key-value")
            }
        }
    }

    func retrieveConduit(conduit: String, key: String, single: Bool) {
        guard let connection = connection, isConnected else {
            return
        }

        let payloadData: [String: Any] = [
            "message": "",
            "action": "retrieve",
            "timestamp": "\(Date())",
            "target": conduit,
            "key": key,
            "single": single
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: connection, textData: payload) { success in
            if success {
                print("Key-value retrieved")
            } else {
                print("Failed to retrieve key-value")
            }
        }
    }

    func retrieveKeyValue(key: String) {
        guard let connection = connection, isConnected else {
            return
        }

        let payloadData: [String: Any] = [
            "key": key,
            "action": "retrieve",
            "timestamp": "\(Date())"
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: connection, textData: payload) { success in
            if success {
                print("Key-value retrieved")
            } else {
                print("Failed to retrieve key-value")
            }
        }
    }

    func receiveMessage(completion: @escaping (String?) -> Void) {
        guard let connection = connection, isConnected else {
            completion(nil)
            return
        }

        recvAsCStructure(connection: connection) { data in
            if let data = data {
                let message = String(data: data, encoding: .utf8)
                completion(message)
            } else {
                completion(nil)
            }
        }
    }

    private func sendAsCStructure(connection: NWConnection, textData: Data, completion: @escaping (Bool) -> Void) {
        let compressedData = textData.compress(withAlgorithm: COMPRESSION_LZ4_RAW)
        let crc32 = calculateCRC32(data: compressedData!)
        let cStruct = CStructure(magic: 0x12344321, size: UInt32(compressedData!.count), checksum: crc32)

        var cStructData = Data()
        withUnsafeBytes(of: cStruct) { pointer in
            cStructData.append(contentsOf: pointer)
        }

        connection.send(content: cStructData, completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send C structure: \(error.localizedDescription)")
                completion(false)
            } else {
                connection.send(content: compressedData, completion: .contentProcessed { error in
                    if let error = error {
                        print("Failed to send text: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        completion(true)
                    }
                })
            }
        })
    }

    private func recvAsCStructure(connection: NWConnection, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: MemoryLayout<CStructure>.size, maximumLength: MemoryLayout<CStructure>.size) { data, context, isComplete, error in
            if let data = data {
                var cStruct: CStructure = data.withUnsafeBytes { $0.load(as: CStructure.self) }

                connection.receive(minimumIncompleteLength: Int(cStruct.size), maximumLength: Int(cStruct.size)) { data, context, isComplete, error in
                    if let data = data {
                        let crc32 = self.calculateCRC32(data: data)
                        if crc32 == cStruct.checksum {
                            let decompressedData = data.decompress(withAlgorithm: COMPRESSION_LZ4_RAW)
                            completion(decompressedData)
                        } else {
                            print("Checksum mismatch. Data may be corrupted.")
                            completion(nil)
                        }
                    } else {
                        completion(nil)
                    }
                }
            } else {
                completion(nil)
            }
        }
    }

    private func calculateCRC32(data: Data) -> UInt32 {
        let crcTable: [UInt32] = (0...255).map { i -> UInt32 in
            var crc = i
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return UInt32(crc)
        }

        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[index]
        }

        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    func compress(withAlgorithm algorithm: compression_algorithm) -> Data? {
        let bufferSize = 64 * 1024
        var compressedData = Data()

        self.withUnsafeBytes { (sourcePointer: UnsafeRawBufferPointer) in
            let sourceBuffer = sourcePointer.bindMemory(to: UInt8.self).baseAddress!
            let sourceSize = self.count

            var destinationBuffer = [UInt8](repeating: 0, count: bufferSize)

            let compressedSize = compression_encode_buffer(
                &destinationBuffer,
                bufferSize,
                sourceBuffer,
                sourceSize,
                nil,
                algorithm
            )

            if compressedSize > 0 {
                compressedData.append(destinationBuffer, count: compressedSize)
            }
        }

        return compressedData
    }

    func decompress(withAlgorithm algorithm: compression_algorithm) -> Data? {
        let bufferSize = 64 * 1024
        var decompressedData = Data()

        self.withUnsafeBytes { (sourcePointer: UnsafeRawBufferPointer) in
            let sourceBuffer = sourcePointer.bindMemory(to: UInt8.self).baseAddress!
            let sourceSize = self.count

            var destinationBuffer = [UInt8](repeating: 0, count: bufferSize)

            let decompressedSize = compression_decode_buffer(
                &destinationBuffer,
                bufferSize,
                sourceBuffer,
                sourceSize,
                nil,
                algorithm
            )

            if decompressedSize > 0 {
                decompressedData.append(destinationBuffer, count: decompressedSize)
            }
        }

        return decompressedData
    }
}

struct CStructure {
    var magic: UInt32
    var size: UInt32
    var checksum: UInt32
}
