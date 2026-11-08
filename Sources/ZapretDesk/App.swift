import SwiftUI
import AppKit

@main struct ZapretDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).environmentObject(model.telegram).frame(minWidth:880,minHeight:610)
                .task { await model.refresh(); while !Task.isCancelled {try? await Task.sleep(nanoseconds:3_000_000_000);if !model.busy {await model.refresh()}} }
        }.defaultSize(width:960,height:690).windowStyle(.hiddenTitleBar)
        .commands {CommandGroup(replacing:.newItem){}}
        MenuBarExtra("Zapret Desk",systemImage:model.healthy ? "shield.checkered" : "shield") {
            Text(model.healthy ? "Обход включён" : "Обход выключен")
            Button(model.status?.running == true ? "Выключить обход" : "Включить обход"){model.toggle()}.disabled(!model.online || model.busy)
            Divider()
            Button("Открыть окно"){NSApp.activate(ignoringOtherApps:true);NSApp.windows.first?.makeKeyAndOrderFront(nil)}
            Button("Выйти"){model.telegram.stop();NSApp.terminate(nil)}
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var section = "Главная"
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:28) {
                HStack(spacing:10) {
                    Image(nsImage:NSImage(named:NSImage.applicationIconName) ?? NSImage()).resizable().frame(width:34,height:34)
                    VStack(alignment:.leading,spacing:2){Text("Zapret").font(.system(size:20,weight:.bold,design:.rounded));Text("DESK").font(.system(size:9,weight:.medium)).tracking(3).foregroundStyle(.secondary)}
                }.padding(.top,30)
                VStack(spacing:8){
                    nav("Главная","power")
                    nav("Домены","globe")
                    nav("Настройки","gearshape")
                }
                Spacer()
                Text("Zapret Desk 0.3.1").font(.caption2).foregroundStyle(.tertiary)
            }.padding(.horizontal,18).padding(.bottom,24).frame(width:182).background(Color(red:0.055,green:0.065,blue:0.085))
            Divider().overlay(.white.opacity(0.03))
            VStack(alignment:.leading,spacing:22) {
                HStack {Text(section == "Главная" ? "Подключение" : section).font(.system(size:27,weight:.semibold));Spacer();if model.busy {ProgressView().controlSize(.small)}}
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        switch section {
                        case "Домены": DomainsView()
                        case "Настройки": SettingsView()
                        default: ConnectionView()
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,10)
                }
            }.padding(28).background(Color(red:0.075,green:0.085,blue:0.11))
        }.preferredColorScheme(.dark).tint(.mint)
        .alert("Не удалось выполнить действие",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {Button("Понятно",role:.cancel){model.error = nil}} message:{Text(model.error ?? "")}
    }
    func nav(_ name: String,_ icon: String)->some View {
        Button{section = name}label:{HStack(spacing:10){Image(systemName:icon).frame(width:18);Text(name);Spacer()}.font(.callout).padding(11).foregroundStyle(section == name ? Color.mint : .secondary).background(section == name ? Color.mint.opacity(0.1) : .clear,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var telegram: TelegramService
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:9) {
                        Label(model.healthy ? "Обход включён" : "Обход выключен",systemImage:"circle.fill").font(.caption).foregroundStyle(model.healthy ? .mint : .secondary)
                        Text("Ваше подключение").font(.system(size:26,weight:.medium))
                    }
                    Spacer()
                    Image(systemName:model.healthy ? "shield.checkered" : "shield").font(.system(size:42,weight:.ultraLight)).foregroundStyle(.mint)
                }
                HStack(alignment:.bottom,spacing:14) {
                    VStack(alignment:.leading,spacing:7) {
                        Text("Стратегия").font(.caption).foregroundStyle(.secondary)
                        Picker("Стратегия",selection:$model.selected) {
                            ForEach(model.strategies){row in Text(row.displayName).tag(row.id)}
                        }.labelsHidden().pickerStyle(.menu).controlSize(.large).frame(maxWidth:360,alignment:.leading)
                            .disabled(!model.online || model.busy)
                            .onChange(of:model.selected){_ in
                                if model.online && !model.busy && model.strategies.contains(where:{$0.id == model.selected && !$0.active}) {model.activate()}
                            }
                    }
                    if model.online {
                        Button(model.status?.running == true ? "Выключить" : "Включить"){model.toggle()}.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
                    } else {
                        Button(model.installed ? "Обновить службу" : "Настроить обход"){model.install()}.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
                    }
                }
                if !model.online {Text("Для настройки macOS запросит пароль администратора.").font(.caption).foregroundStyle(.secondary)}
            }.padding(24).background(LinearGradient(colors:[.mint.opacity(0.09),.white.opacity(0.025)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(.mint.opacity(0.16)))
            VStack(alignment:.leading,spacing:15) {
                HStack(spacing:12){Image(systemName:"paperplane.fill").font(.title2).foregroundStyle(.cyan);VStack(alignment:.leading,spacing:4){Text("Telegram").font(.headline);Text(telegram.message).font(.caption).foregroundStyle(.secondary)};Spacer();if telegram.busy {ProgressView().controlSize(.small)}else{Toggle("Telegram-прокси",isOn:Binding(get:{telegram.running},set:{$0 ? telegram.start() : telegram.stop()})).labelsHidden().toggleStyle(.switch)}}
                if telegram.running {HStack {Button("Подключить Telegram"){telegram.connectTelegram()};Text("Подтвердите в Telegram.").font(.caption).foregroundStyle(.secondary)}}
            }.padding(20).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:15))
        }
    }

}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var telegram: TelegramService
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            ImportView()
            GroupBox("Игровой фильтр") {
                VStack(alignment:.leading,spacing:8) {
                    Picker("Режим",selection:Binding(get:{model.gameMode},set:{model.setGameMode($0)})) {
                        Text("Выключен").tag("off");Text("TCP + UDP").tag("all");Text("TCP").tag("tcp");Text("UDP").tag("udp")
                    }.disabled(!model.online || !model.gameAvailable)
                    Text("Для игровых профилей стратегии.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }
            GroupBox("IP-лист") {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Включён",isOn:Binding(get:{model.status?.ipset == "loaded"},set:{model.setIPList($0)})).disabled(!model.online)
                    Text("Обход по списку IP-адресов.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }
            GroupBox("Telegram-прокси") {
                VStack(alignment:.leading,spacing:12){
                    HStack {Text("Локальный порт");Spacer();TextField("1444",value:$telegram.port,formatter:NumberFormatter()).frame(width:100).textFieldStyle(.roundedBorder).disabled(telegram.running || telegram.busy)}
                    Text("Работает, пока открыто приложение.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("Приложение") {
                VStack(alignment:.leading,spacing:12){
                    HStack{Button("Обновить службу"){model.install()};Button("Удалить службу",role:.destructive){model.uninstall()}.disabled(!model.installed)}
                    Text("Обход работает после закрытия окна.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
        }.disabled(model.busy)
    }
}

struct ImportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        GroupBox("Импорт стратегии") {
            VStack(alignment:.leading,spacing:12) {
                Text("Стратегия из файла или ссылки.").font(.caption).foregroundStyle(.secondary)
                HStack {Button("Открыть BAT / TOML…"){model.chooseImport()};Spacer();Button("Экспорт выбранной"){model.exportStrategy()}.disabled(model.selected.isEmpty)}
                HStack {TextField("HTTPS-ссылка на стратегию",text:$model.downloadURL).textFieldStyle(.roundedBorder);Button("Загрузить"){model.download()}.disabled(model.downloadURL.isEmpty)}
                if !model.importText.isEmpty {
                    Text("Стратегия готова к добавлению").font(.caption).foregroundStyle(.mint)
                    TextField("Имя файла.toml",text:$model.importName).textFieldStyle(.roundedBorder)
                    DisclosureGroup("Предпросмотр"){TextEditor(text:$model.importText).font(.system(.caption,design:.monospaced)).frame(height:180)}
                    Button("Добавить стратегию"){model.commitImport()}.buttonStyle(.borderedProminent).disabled(!model.online)
                }
            }.padding(12)
        }
    }
}
struct DomainsView: View {
    @EnvironmentObject var model: AppModel
    @State private var input = ""
    @State private var localError: String?
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Picker("Список",selection:$model.listName) { Text("Мои домены").tag("list-general-user.txt"); Text("Исключения").tag("list-exclude-user.txt") }.pickerStyle(.segmented)
                .onChange(of:model.listName) { _ in model.listLoaded = false; Task {await model.loadList()} }
            Text(model.listName == "list-general-user.txt" ? "Сайты для выбранной стратегии." : "Исключения для стратегии.").font(.caption).foregroundStyle(.secondary)
            GroupBox("Добавить сайты") { VStack(alignment:.leading,spacing:12) { TextField("youtube.com или https://discord.com/channels/…",text:$input).textFieldStyle(.roundedBorder).onSubmit{add()}; HStack { Button("Добавить в список") {add()}; Text("Можно вставить ссылку.").font(.caption).foregroundStyle(.secondary) }; if let localError {Text(localError).foregroundStyle(.orange)} }.padding(12) }
            GroupBox("Пользовательский список") { VStack(alignment:.leading,spacing:12) { TextEditor(text:$model.listText).font(.system(.body,design:.monospaced)).frame(height:300); HStack { Text("Один домен на строку.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Сохранить и применить") {model.saveList()}.buttonStyle(.borderedProminent) } }.padding(12) }
        }.disabled(!model.online || model.busy || !model.listLoaded).task {if model.online {await model.loadList()} }
    }
    func add() { do { try model.addDomains(input); input = ""; localError = nil } catch { localError = error.localizedDescription } }
}
