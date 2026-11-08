import Foundation
import AppKit
import Darwin
import Security

@MainActor final class TelegramService: ObservableObject {
    static let shared = TelegramService()
    @Published var running = false
    @Published var busy = false
    @Published var message = "Выключен"
    @Published var port = 1444
    private var secret = ""
    private var process: Process?
    private var output: FileHandle?
    private var stdin: Pipe?
    private let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ZapretDesk")
    private init() {
        if let data = try? Data(contentsOf:directory.appendingPathComponent("telegram.json")), let config = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] {
            port = config["port"] as? Int ?? 1444; secret = config["secret"] as? String ?? ""
        }
    }
    var link: URL? {URL(string:"tg://proxy?server=127.0.0.1&port=\(port)&secret=\(secret)")}
    func start() {
        guard !busy, process == nil else { return }; busy = true; message = "Запуск…"
        Task { defer { busy = false }; do {
            guard (1024...65535).contains(port) else { throw DeskError(message:"Укажите порт 1024–65535") }
            guard Self.available(port) else {throw DeskError(message:"Порт \(port) уже занят. Выключите другой прокси или выберите другой порт в настройках.")}
            if secret.count != 32 {
                var bytes = [UInt8](repeating:0,count:16)
                guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else {throw DeskError(message:"Не удалось создать ключ прокси")}
                secret = bytes.map{String(format:"%02x",$0)}.joined()
            }
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let config = try JSONSerialization.data(withJSONObject:["port":port,"secret":secret])
            let configURL = directory.appendingPathComponent("telegram.json")
            try config.write(to:configURL,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:configURL.path)
            let executable = Bundle.main.resourceURL!.appendingPathComponent("TGProxy/tgws")
            guard FileManager.default.isExecutableFile(atPath:executable.path) else {throw DeskError(message:"В сборке отсутствует TG WS Proxy")}
            let log = directory.appendingPathComponent("telegram-runtime.log")
            FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])
            let handle = try FileHandle(forWritingTo:log); try handle.truncate(atOffset:0)
            let p = Process(), input = Pipe(); p.executableURL = executable
            p.standardInput = input; p.standardOutput = handle; p.standardError = handle
            p.terminationHandler = { [weak self] child in Task { @MainActor in
                guard let self, self.process === child else {return}
                self.process = nil; self.running = false; self.stdin = nil
                try? self.output?.close(); self.output = nil
                if child.terminationStatus != 0 {self.message = "Прокси остановился с ошибкой. Проверьте порт или перезапустите."}
                else {self.message = "Выключен"}
            } }
            try p.run(); process = p; output = handle; stdin = input
            var request = try JSONSerialization.data(withJSONObject:["port":port,"secret":secret,"log":directory.appendingPathComponent("telegram.log").path]); request.append(10)
            try input.fileHandleForWriting.write(contentsOf:request); try input.fileHandleForWriting.close()
            for _ in 0..<100 {
                guard process === p, p.isRunning else {throw DeskError(message:"Не удалось запустить встроенный TG WS Proxy")}
                if !Self.available(port) {running = true; message = "Работает";return}
                try await Task.sleep(nanoseconds:200_000_000)
            }
            stop();throw DeskError(message:"Прокси не открыл порт за 20 секунд")
        } catch { message = error.localizedDescription; stop(keepMessage:true) } }
    }
    func stop(keepMessage: Bool = false) {
        let p = process; process = nil; running = false; stdin = nil
        if p?.isRunning == true {p?.terminate()}
        try? output?.close(); output = nil
        if !keepMessage {message = "Выключен"}
    }
    func connectTelegram() {if running, let link {NSWorkspace.shared.open(link)}}
    static func available(_ port: Int) -> Bool {
        let fd = socket(AF_INET,SOCK_STREAM,0);guard fd>=0 else{return false};defer{Darwin.close(fd)}
        var addr = sockaddr_in();addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size);addr.sin_family = sa_family_t(AF_INET);addr.sin_port = UInt16(clamping:port).bigEndian;addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}} == 0
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {TelegramService.shared.stop()}
}
