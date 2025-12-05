import SwiftUI
import Combine
import Network
import Security

struct ContentView: View {
    @StateObject private var server = NativeHTTPSServer()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("WebRTC HTTPS 服务器")
                .font(.title2.bold())
            
            // 状态指示
            HStack {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(server.isRunning ? "运行中" : "已停止")
                    .foregroundColor(server.isRunning ? .green : .gray)
            }
            .font(.headline)
            
            // 服务器地址
            if server.isRunning {
                VStack(spacing: 8) {
                    Text(server.serverURL)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    
                    Button("复制地址") {
                        UIPasteboard.general.string = server.serverURL
                        server.addLog("📋 地址已复制")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // 控制按钮
            HStack(spacing: 16) {
                Button(action: {
                    server.startServer()
                }) {
                    Label("启动", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(server.isRunning)
                
                Button(action: {
                    server.stopServer()
                }) {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!server.isRunning)
            }
            .padding(.vertical, 8)
            
            // 错误信息
            if let error = server.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // 日志区域
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("日志")
                        .font(.headline)
                    Spacer()
                    Button("清空") {
                        server.clearLogs()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(server.logs) { log in
                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(log.color)
                                    .id(log.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: server.logs.count) {
                        if let lastLog = server.logs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .frame(maxHeight: 250)
            }
            
            Spacer()
            
            // 使用说明
            VStack(spacing: 4) {
                Text("使用说明")
                    .font(.caption.bold())
                Text("1. 点击启动服务器")
                Text("2. 电脑浏览器访问显示的地址")
                Text("3. 忽略证书警告，继续访问")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Log Entry
struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let color: Color
    let timestamp: Date
    
    init(_ message: String, type: LogType = .info) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        self.message = "[\(time)] \(message)"
        self.timestamp = Date()
        
        switch type {
        case .info: self.color = .primary
        case .success: self.color = .green
        case .warning: self.color = .orange
        case .error: self.color = .red
        case .connection: self.color = .blue
        }
    }
    
    enum LogType {
        case info, success, warning, error, connection
    }
}

// MARK: - Native HTTPS Server
class NativeHTTPSServer: ObservableObject {
    @Published var isRunning = false
    @Published var serverURL = ""
    @Published var errorMessage: String?
    @Published var logs: [LogEntry] = []
    
    private var listener: NWListener?
    private let port: UInt16 = 8443
    private var htmlContent: String = ""
    private var connectionCount = 0
    
    init() {
        loadHTML()
        addLog("📱 服务器初始化完成", type: .info)
        addLog("💡 点击「启动」按钮开始", type: .info)
    }
    
    func addLog(_ message: String, type: LogEntry.LogType = .info) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(message, type: type))
            // 保留最近 100 条日志
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
    }
    
    func clearLogs() {
        logs.removeAll()
        addLog("🗑️ 日志已清空", type: .info)
    }
    
    private func loadHTML() {
        if let path = Bundle.main.path(forResource: "webRTC", ofType: "html"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            htmlContent = content
            addLog("✅ webRTC.html 加载成功", type: .success)
        } else {
            htmlContent = """
            <!DOCTYPE html>
            <html><body>
            <h1>webRTC.html 未找到</h1>
            <p>请确保 webRTC.html 已添加到项目中</p>
            </body></html>
            """
            addLog("⚠️ webRTC.html 未找到", type: .warning)
        }
    }
    
    func startServer() {
        guard !isRunning else {
            addLog("⚠️ 服务器已在运行中", type: .warning)
            return
        }
        
        errorMessage = nil
        addLog("🚀 正在启动服务器...", type: .info)
        
        do {
            // 加载 PKCS12 证书
            guard let identity = loadIdentity() else {
                DispatchQueue.main.async {
                    self.errorMessage = "无法加载证书"
                    self.addLog("❌ 证书加载失败，请确保 server.p12 已添加到项目", type: .error)
                }
                return
            }
            addLog("🔐 证书加载成功", type: .success)
            
            // 创建 TLS 参数
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, identity)
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            
            let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        if let ip = self?.getWiFiAddress() {
                            self?.serverURL = "https://\(ip):\(self?.port ?? 8443)/"
                            self?.addLog("✅ 服务器启动成功", type: .success)
                            self?.addLog("🌐 地址: https://\(ip):\(self?.port ?? 8443)/", type: .info)
                        } else {
                            self?.serverURL = "https://localhost:\(self?.port ?? 8443)/"
                            self?.addLog("⚠️ 无法获取 WiFi IP，请检查网络连接", type: .warning)
                        }
                    case .failed(let error):
                        self?.errorMessage = "服务器错误: \(error.localizedDescription)"
                        self?.addLog("❌ 服务器错误: \(error.localizedDescription)", type: .error)
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                        self?.addLog("🛑 服务器已停止", type: .info)
                    case .waiting(let error):
                        self?.addLog("⏳ 等待中: \(error.localizedDescription)", type: .warning)
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "启动失败: \(error.localizedDescription)"
                self.addLog("❌ 启动失败: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    func stopServer() {
        guard isRunning else {
            addLog("⚠️ 服务器未在运行", type: .warning)
            return
        }
        
        addLog("🛑 正在停止服务器...", type: .info)
        listener?.cancel()
        listener = nil
        isRunning = false
        serverURL = ""
        connectionCount = 0
    }
    
    private func loadIdentity() -> sec_identity_t? {
        guard let p12Path = Bundle.main.path(forResource: "server", ofType: "p12"),
              let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else {
            return nil
        }
        
        let options: [String: Any] = [kSecImportExportPassphrase as String: "123456"]
        var items: CFArray?
        
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess,
              let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first,
              let secIdentity = firstItem[kSecImportItemIdentity as String] else {
            return nil
        }
        
        let identity = sec_identity_create(secIdentity as! SecIdentity)
        return identity
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connectionCount += 1
        let connId = connectionCount
        
        // 获取客户端信息
        var clientInfo = "未知"
        if case .hostPort(let host, let port) = connection.endpoint {
            clientInfo = "\(host):\(port)"
        }
        
        connection.start(queue: .global(qos: .userInitiated))
        
        // 监听连接状态，静默处理 TLS 握手失败
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // TLS 握手成功，记录连接
                self?.addLog("🔗 [\(connId)] 连接: \(clientInfo)", type: .connection)
            case .failed(let error):
                // 静默处理证书错误（浏览器首次访问时的正常行为）
                let errorDesc = error.localizedDescription.lowercased()
                if errorDesc.contains("certificate") || errorDesc.contains("tls") || errorDesc.contains("ssl") {
                    // 忽略证书相关错误，这是自签名证书的正常现象
                } else {
                    self?.addLog("⚠️ [\(connId)] 连接失败", type: .warning)
                }
                connection.cancel()
            case .cancelled:
                break
            default:
                break
            }
        }
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            
            if let data = data, let request = String(data: data, encoding: .utf8) {
                // 解析请求路径
                let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                
                // 只记录有效的 HTTP 请求
                if firstLine.hasPrefix("GET") || firstLine.hasPrefix("POST") {
                    self.addLog("📥 [\(connId)] \(firstLine.prefix(40))", type: .info)
                }
                
                // 发送 HTTP 响应
                let responseBody = self.htmlContent
                let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Content-Length: \(responseBody.utf8.count)\r
                Connection: close\r
                Access-Control-Allow-Origin: *\r
                \r
                \(responseBody)
                """
                
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
                    self?.addLog("📤 [\(connId)] 已响应", type: .success)
                    connection.cancel()
                })
            } else if error != nil {
                // 静默处理接收错误（通常是 TLS 相关）
                connection.cancel()
            } else if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

#Preview {
    ContentView()
}
