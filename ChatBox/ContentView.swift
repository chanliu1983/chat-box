import SwiftUI

struct ContentView: View {
    @StateObject private var serverCommunicator = ServerCommunicator()
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
            Text(serverCommunicator.isConnected ? "Connected" : "Disconnected")
                .foregroundColor(serverCommunicator.isConnected ? .green : .red)

            HStack {
                Button("Connect") {
                    if serverCommunicator.isConnected || serverCommunicator.isConnecting {
                        return
                    }

                    connectServer()
                }
                .disabled(serverCommunicator.isConnected || serverCommunicator.isConnecting)

                Button("Disconnect") {
                    serverCommunicator.stopConnection()
                }
                
                HStack {
                    Toggle("Conduit 1", isOn: $isInConduit1)
                        .onChange(of: isInConduit1) { _ in
                            serverCommunicator.joinConduit(conduit: "Conduit 1", isConnect: isInConduit1)
                        }
                    Toggle("Conduit 2", isOn: $isInConduit2)
                        .onChange(of: isInConduit2) { _ in
                            serverCommunicator.joinConduit(conduit: "Conduit 2", isConnect: isInConduit2)
                        }
                    Toggle("Conduit 3", isOn: $isInConduit3)
                        .onChange(of: isInConduit3) { _ in
                            serverCommunicator.joinConduit(conduit: "Conduit 3", isConnect: isInConduit3)
                        }
                }
            }

            TextField("Message To Send", text: $message)

            HStack {
                Button("Send") {
                    if isInConduit1 {
                        serverCommunicator.sendMessage(message: message, conduit: "Conduit 1") { success in
                            if success {
                                print("Message sent successfully")
                            } else {
                                print("Failed to send message")
                            }
                        }
                    }
                    if isInConduit2 {
                        serverCommunicator.sendMessage(message: message, conduit: "Conduit 2") { success in
                            if success {
                                print("Message sent successfully")
                            } else {
                                print("Failed to send message")
                            }
                        }
                    }
                    if isInConduit3 {
                        serverCommunicator.sendMessage(message: message, conduit: "Conduit 3") { success in
                            if success {
                                print("Message sent successfully")
                            } else {
                                print("Failed to send message")
                            }
                        }
                    }
                }

                Button("Storm") {
                    DispatchQueue.global(qos: .background).async {
                        isStormOngoing = true
                        for i in 0..<100 {
                            if !serverCommunicator.isConnected && !serverCommunicator.isConnecting {
                                isStormOngoing = false
                                break
                            }
                            
                            serverCommunicator.stormConduit(conduit: "Conduit 1", count: i, message: message)
                            serverCommunicator.stormConduit(conduit: "Conduit 2", count: i, message: message)
                            serverCommunicator.stormConduit(conduit: "Conduit 3", count: i, message: message)
                            Thread.sleep(forTimeInterval: 1)
                        }
                        isStormOngoing = false
                    }
                }
                .disabled(isStormOngoing)
            }

            HStack {
                TextField("Key", text: $key)
                Button("store") {
                    if isInConduit1 {
                        serverCommunicator.storeConduit(conduit: "Conduit 1", message: message, key: key)
                    }
                    if isInConduit2 {
                        serverCommunicator.storeConduit(conduit: "Conduit 2", message: message, key: key)
                    }
                    if isInConduit3 {
                        serverCommunicator.storeConduit(conduit: "Conduit 3", message: message, key: key)
                    }
                }

                Button("retrieve") {
                    if isInConduit1 {
                        serverCommunicator.retrieveConduit(conduit: "Conduit 1", key: key, single: isSingleRetrievalEnabled)
                    }
                    if isInConduit2 {
                        serverCommunicator.retrieveConduit(conduit: "Conduit 2", key: key, single: isSingleRetrievalEnabled)
                    }
                    if isInConduit3 {
                        serverCommunicator.retrieveConduit(conduit: "Conduit 3", key: key, single: isSingleRetrievalEnabled)
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
            serverCommunicator.stopConnection()
        }
        .onAppear {
            connectServer()
        }
    }

    func connectServer() {
        if serverCommunicator.isConnected || serverCommunicator.isConnecting {
            return
        }

        let host = serverType == "Linux" ? "192.168.10.106" : "192.168.10.64"
        serverCommunicator.startConnection(host: host, port: 16666) { success in
            if success {
                print("Connected to server")

                serverCommunicator.joinConduit(conduit: "Conduit 1", isConnect: isInConduit1)
                serverCommunicator.joinConduit(conduit: "Conduit 2", isConnect: isInConduit2)
                serverCommunicator.joinConduit(conduit: "Conduit 3", isConnect: isInConduit3)

                receiveMessages()

                func receiveMessages() {
                    serverCommunicator.receiveMessage { message in
                        if let message = message {
                        let data = message.data(using: .utf8)
                            if let json = try? JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] {
                            if let source = json["source"] as? Int64, let message = json["message"] as? String, let timestamp = json["timestamp"] as? String {
                                let parsedMessage = "\(source): \(message) at (\(timestamp))"
                                messages.insert(parsedMessage, at: 0)

                                // Continue to receive more data
                                receiveMessages()
                            }
                        }
                        } else {
                            print("Failed to receive message")
                        }
                    }
                }
            } else {
                print("Failed to connect to server")
            }
        }
    }
}
