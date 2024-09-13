import Network
import SwiftUI
import Foundation
import Compression

extension Data {
    func compress(withAlgorithm algorithm: compression_algorithm) -> Data? {
        let bufferSize = 64 * 1024  // 64 KB buffer size
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
        let bufferSize = 64 * 1024  // 64 KB buffer size
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

struct ContentView: View {
    @State private var connection: NWConnection? = nil
    @State private var isConnected: Bool = false
    @State private var isConnecting: Bool = false
    @State private var message: String = "Test Message Sent!!!"
    @State private var messages: [String] = []
    @State private var key: String = "TestbedKey1"
    @State private var serverType: String = "Linux"
    @State private var isSingleRetrievalEnabled: Bool = false
    @State private var isStormOngoing: Bool = false
    @State private var isInConduit1: Bool = true
    @State private var isInConduit2: Bool = false
    @State private var isInConduit3: Bool = false

    var body: some View {
        Picker("Platform", selection: $serverType) {
            Text("Linux").tag("Linux")
            Text("Mac").tag("Mac")
        }
        .pickerStyle(SegmentedPickerStyle())

        VStack {
            Text(isConnected ? "Connected" : "Disconnected")
                .foregroundColor(isConnected ? .green : .red)
            
            HStack {
                Button("Connect") {
                    if self.isConnected || self.isConnecting {
                        // do nothing if already connected or connecting
                        return
                    }

                    self.isConnecting = true
                    startConnection()
                }
                .disabled(self.isConnected || self.isConnecting)
                
                Button("Disconnect") {
                    stopConnection()
                }

                HStack {
                    Toggle("Conduit 1", isOn: $isInConduit1)
                        .onChange(of: isInConduit1) { _ in
                            joinConduit()
                        }
                    Toggle("Conduit 2", isOn: $isInConduit2)
                        .onChange(of: isInConduit2) { _ in
                            joinConduit()
                        }
                    Toggle("Conduit 3", isOn: $isInConduit3)
                        .onChange(of: isInConduit3) { _ in
                            joinConduit()
                        }
                }
            }
            
            TextField(
                "Message To Send",
                text: $message
            )
            
            HStack {
                Button("Send") {
                    if isInConduit1 {
                        sendToConduit(conduit: "Conduit 1")
                    }
                    if isInConduit2 {
                        sendToConduit(conduit: "Conduit 2")
                    }
                    if isInConduit3 {
                        sendToConduit(conduit: "Conduit 3")
                    }
                }
                
                Button("Storm") {
                    DispatchQueue.global(qos: .background).async {
                        // Check if storm is already ongoing
                        guard !self.isStormOngoing else {
                            return
                        }
                        
                        // Set the storm status to ongoing
                        self.isStormOngoing = true
                        
                        for i in 0..<100 {
                            if self.isInConduit1 {
                                self.stormConduit(conduit: "Conduit 1", message: self.message, count: i)
                            }
                            if self.isInConduit2 {
                                self.stormConduit(conduit: "Conduit 2", message: self.message, count: i)
                            }
                            if self.isInConduit3 {
                                self.stormConduit(conduit: "Conduit 3", message: self.message, count: i)
                            }
                            Thread.sleep(forTimeInterval: 1) // Sleep for 1 second
                        }
                        
                        // Set the storm status to not ongoing
                        self.isStormOngoing = false
                    }
                }
                .disabled(self.isStormOngoing)
            }
            
            HStack {
                TextField("Key", text: $key)
                Button("store") {
                    if isInConduit1 {
                        storeConduit(conduit: "Conduit 1", message: message, key: key)
                    }
                    if isInConduit2 {
                        storeConduit(conduit: "Conduit 2", message: message, key: key)
                    }
                    if isInConduit3 {
                        storeConduit(conduit: "Conduit 3", message: message, key: key)
                    }
                }
                
                Button("retrieve") {
                    if isInConduit1 {
                        retrieveConduit(conduit: "Conduit 1", key: key, single: isSingleRetrievalEnabled)
                    }
                    if isInConduit2 {
                        retrieveConduit(conduit: "Conduit 2", key: key, single: isSingleRetrievalEnabled)
                    }
                    if isInConduit3 {
                        retrieveConduit(conduit: "Conduit 3", key: key, single: isSingleRetrievalEnabled)
                    }
                }
                
                Toggle("Enable Single Retrieval", isOn: $isSingleRetrievalEnabled)
            }
            
            ScrollView {
                VStack {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                    }
                }
            }
        }
        .padding()
        .onDisappear {
            stopConnection() // Clean up when the view disappears
        }
        .onAppear {
            startConnection() // Start the connection when the view appears
        }
    }
    
    func startReceiving(connection: NWConnection) {
        // use RecvAsCStructure to receive the data
        recvAsCStructure(connection: connection) { data in
            if let data = data {
                print(String(data: data, encoding: .utf8))
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let source = json["source"] as? Int64, let message = json["message"] as? String, let timestamp = json["timestamp"] as? String {
                        let parsedMessage = "\(source): \(message) at (\(timestamp))"
                        messages.insert(parsedMessage, at: 0)

                        // Continue to receive more data
                        startReceiving(connection: connection)
                    }
                }
            }
        }
    }

    func startConnection() {
        // let ip4 = IPv4Address("192.168.10.106")! // Linux
        // let ip4 = IPv4Address("192.168.10.64")! // Mac
        let ip4: IPv4Address
        if serverType == "Linux" {
            ip4 = IPv4Address("192.168.10.106")!
        } else {
            ip4 = IPv4Address("192.168.10.64")!
        }

        let host = NWEndpoint.Host.ipv4(ip4)
        let port = NWEndpoint.Port(rawValue: 16666)

        if connection == nil {
            connection = NWConnection(host: host, port: port!, using: .tcp)
        } else {
            // close and deallocate the previous connection
            connection?.cancel()
            connection = nil
            
            connection = NWConnection(host: host, port: port!, using: .tcp)
        }

        if let connection = connection {
            // Use [weak self] to capture self as a weak reference and avoid immutability issues
            connection.stateUpdateHandler = { [self] newState in
            DispatchQueue.main.async {
                switch newState {
                case .ready:
                self.isConnected = true
                self.isConnecting = false
                self.joinConduit()
                self.startReceiving(connection: connection)
                    
                case .failed(_), .cancelled:
                self.isConnected = false
                self.isConnecting = false
                default:
                break
                }
            }
            }
            
            connection.start(queue: .global())
        }
    }

    func stopConnection() {
        connection?.cancel()
        isConnected = false
        isConnecting = false
    }

    func joinConduit() {
        if isInConduit1 {
            let payloadData: [String: Any] = [
                "message": "Conduit 1",
                "action": "connect",
                "timestamp": "\(Date())"
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
        } else {
            let payloadData: [String: Any] = [
                "message": "Conduit 1",
                "action": "disconnect",
                "timestamp": "\(Date())"
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
        }
        if isInConduit2 {
            let payloadData: [String: Any] = [
                "message": "Conduit 2",
                "action": "connect",
                "timestamp": "\(Date())"
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
        } else {
            let payloadData: [String: Any] = [
                "message": "Conduit 2",
                "action": "disconnect",
                "timestamp": "\(Date())"
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
        }
        if isInConduit3 {
            let payloadData: [String: Any] = [
                "message": "Conduit 3",
                "action": "connect",
                "timestamp": "\(Date())"
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
        } else {
            let payloadData: [String: Any] = [
                "message": "Conduit 3",
                "action": "disconnect",
                "timestamp": "\(Date())"
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
        }
    }
    
    func sendToConduit(conduit: String) {
        let payloadData: [String: Any] = [
            "message": message,
            "action": "send",
            "timestamp": "\(Date())",
            "target": conduit
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: self.connection!, textData: payload)
    }

    func stormConduit(conduit: String, message: String, count: Int) {
        let payloadData: [String: Any] = [
                "message": "Storm \(count) : \(message)",
                "action": "send",
                "timestamp": "\(Date())",
                "target": conduit
            ]
            let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
            sendAsCStructure(connection: self.connection!, textData: payload)
    }

    func storeConduit(conduit: String, message: String, key: String) {
        let payloadData: [String: Any] = [
            "message": message,
            "action": "store",
            "timestamp": "\(Date())",
            "target": conduit,
            "key": key
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: self.connection!, textData: payload)
    }

    func retrieveConduit(conduit: String, key: String, single: Bool) {
        let payloadData: [String: Any] = [
            "message": "",
            "action": "retrieve",
            "timestamp": "\(Date())",
            "target": conduit,
            "key": key,
            "single": single
        ]
        let payload = try! JSONSerialization.data(withJSONObject: payloadData, options: [])
        sendAsCStructure(connection: self.connection!, textData: payload)
    }
}


// Define the C structure
struct CStructure {
    var magic: UInt32
    var size: UInt32
    var checksum: UInt32
}

func calculateCRC32(data: Data) -> UInt32 {
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

func sendAsCStructure(connection: NWConnection, textData: Data) {
    let compressedData = textData.compress(withAlgorithm: COMPRESSION_LZ4_RAW)
    // let compressedData = textData
    let crc32 = calculateCRC32(data: compressedData!)
    let cStruct = CStructure(magic: 0x12344321, size: UInt32(compressedData!.count), checksum: crc32)
    
    // Convert the C structure to Data
    var cStructData = Data()
    withUnsafeBytes(of: cStruct) { pointer in
        cStructData.append(contentsOf: pointer)
    }
    
    // Send the C structure data over the network
    connection.send(content: cStructData, completion: .contentProcessed { error in
        if let error = error {
            print("Failed to send C structure: \(error.localizedDescription)")
        } else {
            print("C structure sent successfully.")
        }
    })

    // print size of the compressed data
    print("Compressed data size: \(compressedData!.count)")
    
    // then send the text as data
    connection.send(content: compressedData, completion: .contentProcessed { error in
        if let error = error {
            print("Failed to send text: \(error.localizedDescription)")
        } else {
            print("Text sent successfully.")
            print("Compressed data:")
            for byte in compressedData! {
                print(String(byte, radix: 16, uppercase: false), terminator: "")
            }
            print("\n")
        }
    })
}

func recvAsCStructure(connection: NWConnection, completion: @escaping (Data?) -> Void) {
    connection.receive(minimumIncompleteLength: MemoryLayout<CStructure>.size, maximumLength: MemoryLayout<CStructure>.size) { data, context, isComplete, error in
        if let data = data {
            var cStruct: CStructure = data.withUnsafeBytes { $0.load(as: CStructure.self) }
            
            // Receive the compressed data
            connection.receive(minimumIncompleteLength: Int(cStruct.size), maximumLength: Int(cStruct.size)) { data, context, isComplete, error in
                if let data = data {
                    let crc32 = calculateCRC32(data: data)
                    if crc32 == cStruct.checksum {
                        let decompressedData = data.decompress(withAlgorithm: COMPRESSION_LZ4_RAW)
                        completion(decompressedData)
                    } else {
                        print("Checksum mismatch. Data may be corrupted.")
                        completion(nil)
                    }
                }
                if let error = error {
                    print("Receive error: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
        if let error = error {
            print("Receive error: \(error.localizedDescription)")
            completion(nil)
        }
    }
}
