import Foundation
import AppKit

struct DeskError: LocalizedError { let message: String; var errorDescription: String? { message } }

struct StrategyRow: Identifiable, Decodable {
    var id: String { path ?? name }
    var displayName: String {
        guard let path else { return name }
        let filename = URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent
        return filename == name ? name : name + " · " + filename
    }
    let name: String
    let path: String?
    let description: String?
    let profiles: Int
    let ops: [String]?
    let unsupported: [String]?
    let active: Bool
}
struct ListResult: Decodable { let strategies: [StrategyRow] }
struct Status: Decodable {
    let running: Bool
    let transport: String
    let strategy: String
    let ipset: String?
    let window_tcp: [String]?
    let window_udp: [String]?
    let warnings: [String]?
    let unsupported: [String]?
    let stats: Stats
    struct Stats: Decodable { let pkts_in: Int; let pkts_inject: Int; let desyncs: Int; let errors: Int }
}

// All blocking subprocess I/O runs off the UI thread. No imported content enters a shell.
enum Runner {
    static func run(_ executable: URL, _ arguments: [String] = [], input: Data? = nil, timeout: TimeInterval = 100, allowFailure: Bool = false) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process(), output = Pipe(), stdin = Pipe()
            process.executableURL = executable; process.arguments = arguments
            process.standardOutput = output; process.standardError = output
            if input != nil { process.standardInput = stdin }
            try process.run()
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            if let input { try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); timer.cancel()
            guard allowFailure || process.terminationStatus == 0 else { throw DeskError(message: String(data: data, encoding: .utf8) ?? "Процесс завершился с ошибкой") }
            return data
        }.value
    }
    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func admin(_ script: String) async throws {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        _ = try await run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", "do shell script \"\(escaped)\" with administrator privileges"], timeout: 300)
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var status: Status?
    @Published var strategies: [StrategyRow] = []
    @Published var selected = ""
    @Published var error: String?
    @Published var notice = ""
    @Published var busy = false
    @Published var online = false
    @Published var listText = ""
    @Published var listName = "list-general-user.txt"
    @Published var importText = ""
    @Published var importName = ""
    @Published var downloadURL = ""
    @Published var gameMode = "off"
    @Published var gameAvailable = false
    @Published var previewRows: [StrategyRow] = []
    @Published var listLoaded = false
    let telegram = TelegramService.shared
    let dataRoot = "/Library/Application Support/ZapretDesk"
    var resources: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath) }
    var backend: URL { resources.appendingPathComponent("bin") }
    var seed: URL { resources.appendingPathComponent("Data") }
    var installed: Bool { FileManager.default.fileExists(atPath: dataRoot + "/bin/zapretd") }
    var healthy: Bool { status?.running == true && status?.transport == "divert" && !(status?.window_udp ?? []).isEmpty && (status?.unsupported ?? []).isEmpty }

    func rpc(_ cmd: String, args: [String: String] = [:]) async throws -> Data {
        let request = try JSONSerialization.data(withJSONObject: ["cmd":cmd, "args":args])
        let data = try await Runner.run(backend.appendingPathComponent("deskbridge"), input: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String:Any], object["ok"] as? Bool == true else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
            throw DeskError(message: object?["error"] as? String ?? "Не удалось прочитать ответ службы")
        }
        return try JSONSerialization.data(withJSONObject: object["data"] ?? [:], options: [.prettyPrinted, .sortedKeys])
    }
    func action(_ body: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { try await body() } catch { self.error = error.localizedDescription } }
    }
    func refresh() async {
        do {
            let data = try await rpc("status")
            status = try JSONDecoder().decode(Status.self, from: data); online = true
            let list = try await rpc("list")
            strategies = try JSONDecoder().decode(ListResult.self, from: list).strategies
            if let data = try? await rpc("desk-game-filter"), let value = try? JSONSerialization.jsonObject(with:data) as? [String:String] {gameMode = value["mode"] ?? "off";gameAvailable = true} else {gameAvailable = false}
            if selected.isEmpty || !strategies.contains(where: { $0.id == selected }) { selected = strategies.first(where: { $0.active })?.id ?? strategies.first?.id ?? "" }
        } catch { online = false; status = nil }
    }
    func install() {
        let keepStopped = online && status?.running == false
        let firstInstall = !installed
        action {
            guard FileManager.default.fileExists(atPath: self.backend.appendingPathComponent("zapretd").path) else { throw DeskError(message: "Нет встроенного движка. Соберите .app скриптом scripts/build.sh") }
            let root = Runner.shellQuote(self.dataRoot)
            // Install only our own files; existing domain lists and strategies survive upgrades.
            let script = "set -e\n/usr/bin/install -d -m 755 \(root) \(root)/bin \(root)/lists \(root)/fakes \(root)/strategies\n" +
                "[ ! -L \(root) ]\n/usr/bin/ditto \(Runner.shellQuote(self.backend.path)) \(root)/bin\n" +
                "for category in lists fakes strategies; do for f in \(Runner.shellQuote(self.seed.path))/\"$category\"/*; do [ -f \"$f\" ] || continue; dest=\(root)/\"$category\"/\"${f##*/}\"; [ -e \"$dest\" ] || /usr/bin/install -m 644 \"$f\" \"$dest\"; done; done\n" +
                "while read -r expected name; do dest=\(root)/strategies/\"$name\"; [ -f \"$dest\" ] || continue; actual=$(/usr/bin/shasum -a 256 \"$dest\"); actual=${actual%% *}; if [ \"$actual\" = \"$expected\" ]; then /usr/bin/install -m 644 \(Runner.shellQuote(self.seed.path))/strategies/\"$name\" \"$dest\"; fi; done < \(Runner.shellQuote(self.seed.appendingPathComponent("strategy-migrations.tsv").path))\n" +
                "if [ -f \(root)/strategies/mac-balanced.toml ]; then /usr/bin/install -d -m 755 \(root)/retired; /bin/mv \(root)/strategies/mac-balanced.toml \(root)/retired/mac-balanced-$(date +%s).toml; fi\n" +
                "/usr/sbin/chown -R root:wheel \(root)\n/bin/chmod -R go-w \(root)\n" +
                "\(root)/bin/zapretd install-daemon --data \(root) --transport divert --log /var/log/zapretdesk.log"
            try await Runner.admin(script)
            self.notice = "Служба установлена"
            for _ in 0..<20 { await self.refresh(); if self.online { break }; try await Task.sleep(nanoseconds: 500_000_000) }
            if firstInstall && self.online {_ = try await self.rpc("use",args:["name":"general-alt13"]);self.selected = "";await self.refresh()}
            if keepStopped && self.online {_ = try await self.rpc("stop"); await self.refresh()}
        }
    }
    func toggle() {
        action {
                        if self.status?.running == true { _ = try await self.rpc("stop"); self.notice = "Обработка остановлена" }
            else {
                if let row = self.strategies.first(where:{$0.id == self.selected}), !row.active, let path = row.path {
                    _ = try await self.rpc("use",args:["name":URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent])
                }
                _ = try await self.rpc("start", args: ["transport":"divert"]); self.notice = "Запрошен запуск TCP + UDP" }
            await self.refresh()
        }
    }
    func activate() {
        action {
                        guard let row = self.strategies.first(where: { $0.id == self.selected }), let path = row.path else { return }
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            _ = try await self.rpc("use", args: ["name":name]); self.notice = "Выбрана стратегия «\(row.name)»"; await self.refresh()
        }
    }
    func loadList() async {
        do {
            let data = try await rpc("desk-list-read", args: ["name":listName])
            let object = try JSONSerialization.jsonObject(with: data) as? [String:String]
            listText = object?["text"] ?? ""; listLoaded = true
        } catch { listLoaded = false; self.error = error.localizedDescription }
    }
    func saveList() {
        action {
            let data = try await self.rpc("desk-list-write", args:["name":self.listName, "text":self.listText])
            self.listText = ((try JSONSerialization.jsonObject(with:data)) as? [String:String])?["text"] ?? self.listText
            self.notice = "Список сохранён и применён без перезапуска приложения"; await self.refresh()
        }
    }
    func addDomains(_ input: String) throws {
        var domains = [String]()
        for item in input.components(separatedBy: .newlines) {
            var value = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.isEmpty { continue }
            if value.contains("://") { guard let host = URL(string:value)?.host else { throw DeskError(message: "Некорректный URL: \(item)") }; value = host }
            if value.hasPrefix("*.") { value.removeFirst(2) }
            if value.hasSuffix(".") { value.removeLast() }
            if let host = URL(string:"https://\(value)")?.host { value = host }
            guard value.range(of: #"^\^?[a-z0-9]([a-z0-9.-]*[a-z0-9])?$"#, options: .regularExpression) != nil, value.contains(".") else { throw DeskError(message:"Некорректный домен: \(item)") }
            domains.append(value)
        }
        let old = listText.split(separator:"\n").map(String.init).filter { !$0.hasPrefix("#") }
        listText = Array(Set(old + domains)).sorted().joined(separator:"\n") + "\n"
    }
    func chooseImport() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension:"bat")!, .init(filenameExtension:"toml")!]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { action { try await self.prepareImport(data: Data(contentsOf:url), name:url.lastPathComponent) } }
    }
    func download() {
        action {
            guard var url = URL(string:self.downloadURL), url.scheme == "https" else { throw DeskError(message:"Укажите HTTPS-ссылку на .bat или .toml") }
            if url.host == "github.com" {
                let parts = url.pathComponents.filter { $0 != "/" }
                if parts.count >= 5 && parts[2] == "blob" { url = URL(string:"https://raw.githubusercontent.com/" + ([parts[0], parts[1]] + Array(parts.dropFirst(3))).joined(separator:"/"))! }
            }
            guard ["bat","toml"].contains(url.pathExtension.lowercased()) else { throw DeskError(message:"Поддерживаются .bat и .toml") }
            var request = URLRequest(url:url); request.timeoutInterval = 30
            let (bytes, response) = try await URLSession.shared.bytes(for:request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https" else { throw DeskError(message:"Сервер не вернул файл по HTTPS") }
            var data = Data()
            for try await byte in bytes { guard data.count < 500_000 else { throw DeskError(message:"Файл превышает 500 КБ") }; data.append(byte) }
            try await self.prepareImport(data:data,name:url.lastPathComponent)
        }
    }
    func prepareImport(data: Data, name: String) async throws {
        importText = ""; importName = ""
        guard data.count < 500_000, let text = String(data:data,encoding:.utf8) else { throw DeskError(message:"Нужен текстовый UTF-8 файл до 500 КБ") }
        if name.lowercased().hasSuffix("toml") {
            importText = text; importName = "import-" + UUID().uuidString.prefix(8) + ".toml"
        } else {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:temp.appendingPathComponent("in"),withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:temp) }
            let safeName = URL(fileURLWithPath:name).lastPathComponent
            try data.write(to:temp.appendingPathComponent("in").appendingPathComponent(safeName))
            _ = try await Runner.run(backend.appendingPathComponent("batconv"), ["--in",temp.appendingPathComponent("in").path,"--out",temp.appendingPathComponent("out").path,"--lists",seed.appendingPathComponent("lists").path,"--fakes",seed.appendingPathComponent("fakes").path,"--game-filter","off"])
            let files = try FileManager.default.contentsOfDirectory(at:temp.appendingPathComponent("out"),includingPropertiesForKeys:nil).filter { $0.pathExtension == "toml" }
            guard let result = files.first, files.count == 1 else { throw DeskError(message:"BAT не содержит одну поддерживаемую стратегию winws") }
            importText = try String(contentsOf:result,encoding:.utf8)
            importName = "import-" + UUID().uuidString.prefix(8) + ".toml"
        }
        notice = "Импорт подготовлен. Проверьте результат и нажмите «Добавить стратегию»."
    }
    func commitImport() {
        action {
            _ = try await self.rpc("desk-strategy-install",args:["name":self.importName,"text":self.importText])
            self.importText = ""; self.importName = ""; self.notice = "Стратегия добавлена"; await self.refresh()
        }
    }

    func setGameMode(_ mode: String) {
        action {
            _ = try await self.rpc("desk-game-filter",args:["mode":mode])
            await self.refresh()
        }
    }
    func setIPList(_ enabled: Bool) {
        action {
            _ = try await self.rpc("ipset",args:["mode":enabled ? "loaded" : "none"])
            await self.refresh();        }
    }
    func exportStrategy() {
        guard let row = strategies.first(where: { $0.id == selected }), let path = row.path else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath:path).lastPathComponent
        if panel.runModal() == .OK, let url = panel.url {
            do { try Data(contentsOf:URL(fileURLWithPath:path)).write(to:url,options:.atomic) } catch { self.error = error.localizedDescription }
        }
    }
    func uninstall() {
        action {
            let root = Runner.shellQuote(self.dataRoot)
            try await Runner.admin("\(root)/bin/zapretd uninstall-daemon --data \(root) --log /var/log/zapretdesk.log")
            self.notice = "Служба удалена. Стратегии и списки сохранены в \(self.dataRoot)."; await self.refresh()
        }
    }
}

