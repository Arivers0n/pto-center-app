import Foundation
import Security
import SwiftUI

// MARK: - JSON: записи хранятся как есть, чтобы не терять поля, которые знает только веб-версия

enum JSON: Codable, Hashable {
    case s(String), n(Double), b(Bool), o([String: JSON]), a([JSON]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Double.self) { self = .n(v) }
        else if let v = try? c.decode(Bool.self) { self = .b(v) }
        else if let v = try? c.decode(String.self) { self = .s(v) }
        else if let v = try? c.decode([JSON].self) { self = .a(v) }
        else { self = .o(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .s(let v): try c.encode(v)
        case .n(let v): try c.encode(v)
        case .b(let v): try c.encode(v)
        case .o(let v): try c.encode(v)
        case .a(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSON? {
        get { if case .o(let d) = self { return d[key] }; return nil }
        set {
            guard case .o(var d) = self else { return }
            d[key] = newValue
            self = .o(d)
        }
    }

    var str: String {
        switch self {
        case .s(let v): return v
        case .n(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v).replacingOccurrences(of: ".", with: ",")
        case .b(let v): return v ? "да" : "нет"
        default: return ""
        }
    }
    var num: Double? {
        switch self {
        case .n(let v): return v
        case .s(let v): return Double(v.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    var bool: Bool { if case .b(let v) = self { return v }; return false }
    var arr: [JSON] { if case .a(let v) = self { return v }; return [] }
    var obj: [String: JSON] { if case .o(let v) = self { return v }; return [:] }
}

extension Optional where Wrapped == JSON {
    var str: String { self?.str ?? "" }
    var num: Double? { self?.num }
    var arr: [JSON] { self?.arr ?? [] }
}

struct Rec: Identifiable, Hashable {
    let id: String
    var v: JSON
    subscript(key: String) -> JSON? { v[key] }
}

enum Fmt {
    static let iso: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let ru: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "dd.MM.yyyy"; return f }()
    static let ruLong: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM, EEEE"; return f }()
    static func date(_ s: String) -> Date? { iso.date(from: String(s.prefix(10))) }
    static func show(_ s: String) -> String { date(s).map { ru.string(from: $0) } ?? s }
    static var today: String { iso.string(from: Date()) }
    static func num(_ v: Double, _ digits: Int = 2) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "ru_RU"); f.numberStyle = .decimal; f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
    static func uid() -> String { String((0..<7).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! }) }
}

// MARK: - Keychain: токен входа не лежит в открытом виде

enum Keychain {
    private static let service = "ru.artek.ptocenter"
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ key: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard let value, let d = value.data(using: .utf8) else { return }
        var add = q; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Сервер

enum API {
    /// Адрес сервера подставляется при сборке из секрета PTO_SERVER (в коде его нет)
    static let base: String = {
        let s = (Bundle.main.object(forInfoDictionaryKey: "PTOServer") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return s.hasSuffix("/") ? s : s + "/"
    }()

    struct Failure: LocalizedError {
        let message: String; let status: Int
        var errorDescription: String? { message }
    }

    static func request(_ path: String, method: String = "GET", token: String?, body: Data? = nil, timeout: TimeInterval = 30) async throws -> Data {
        guard let url = URL(string: base + path) else { throw Failure(message: "Неверный адрес", status: 0) }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Сервер ответил \(code)"
            throw Failure(message: msg, status: code)
        }
        return data
    }
}

// MARK: - Хранилище: те же данные, что в веб-версии ПТО-центра, с работой без сети

enum SyncState: Equatable { case idle, syncing, offline, error(String) }

private struct Op: Codable, Equatable { let c: String; let id: String; let v: JSON?; let del: Int? }
private struct Change: Decodable { let c: String; let id: String; let rev: Int; let v: JSON?; let del: Int? }
private struct SyncReply: Decodable { let rev: Int; let changes: [Change] }
private struct Cache: Codable { var rev: Int; var cols: [String: [String: JSON]]; var pending: [Op] }
private struct PushBody: Encodable { let ops: [Op] }

@MainActor
final class Store: ObservableObject {
    @Published private(set) var token: String? = Keychain.get("token")
    @Published private(set) var cols: [String: [String: JSON]] = [:]
    @Published private(set) var state: SyncState = .idle
    @Published private(set) var lastSync: Date?

    private var rev = 0
    private var pending: [Op] = []
    private var busy = false
    private var timer: Timer?
    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pto-cache.json")
    }()

    init() { load() }

    var loggedIn: Bool { token != nil }
    var pendingCount: Int { pending.count }

    // чтение
    func list(_ c: String) -> [Rec] { (cols[c] ?? [:]).map { Rec(id: $0.key, v: $0.value) } }
    func get(_ c: String, _ id: String) -> Rec? { cols[c]?[id].map { Rec(id: id, v: $0) } }
    func kv(_ key: String) -> JSON? { cols["kv"]?[key] }
    var cfg: JSON { kv("cfg") ?? .o([:]) }

    // запись: сразу на устройство, на сервер — как только есть связь
    func put(_ c: String, _ rec: Rec) {
        var col = cols[c] ?? [:]; col[rec.id] = rec.v; cols[c] = col
        pending.removeAll { $0.c == c && $0.id == rec.id }
        pending.append(Op(c: c, id: rec.id, v: rec.v, del: nil))
        save(); kick()
    }
    func delete(_ c: String, _ id: String) {
        var col = cols[c] ?? [:]; col[id] = nil; cols[c] = col
        pending.removeAll { $0.c == c && $0.id == id }
        pending.append(Op(c: c, id: id, v: nil, del: 1))
        save(); kick()
    }
    func setKV(_ key: String, _ v: JSON) { put("kv", Rec(id: key, v: v)) }

    // вход и выход
    func login(_ user: String, _ password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["login": user, "password": password])
        let data = try await API.request("api/login", method: "POST", token: nil, body: body)
        guard let t = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String else {
            throw API.Failure(message: "Сервер не прислал ключ входа", status: 0)
        }
        Keychain.set("token", t); token = t
        rev = 0; await sync()
    }
    func logout() {
        if let t = token { Task { _ = try? await API.request("api/logout", method: "POST", token: t) } }
        Keychain.set("token", nil); token = nil; cols = [:]; pending = []; rev = 0; save()
        FileCache.clear()
    }

    // синхронизация
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        Task { await sync() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func kick() { Task { await sync() } }

    func sync() async {
        guard let token, !busy else { return }
        busy = true; state = .syncing
        defer { busy = false }
        do {
            if !pending.isEmpty {
                let ops = pending
                let body = try JSONEncoder().encode(PushBody(ops: ops))
                do {
                    _ = try await API.request("api/center/push", method: "POST", token: token, body: body)
                } catch let e as API.Failure where [400, 403, 413, 422].contains(e.status) {
                    // сервер не примет эти правки никогда (только просмотр, неверный запрос) — не держим очередь вечно
                    for op in ops { if let i = pending.firstIndex(of: op) { pending.remove(at: i) } }
                    throw e
                }
                // во время отправки могли появиться новые правки — убираем только то, что ушло
                for op in ops { if let i = pending.firstIndex(of: op) { pending.remove(at: i) } }
            }
            let data = try await API.request("api/center/sync?since=\(rev)", token: token)
            let reply = try JSONDecoder().decode(SyncReply.self, from: data)
            let waiting = Set(pending.map { $0.c + "#" + $0.id })
            var next = cols
            for ch in reply.changes where !waiting.contains(ch.c + "#" + ch.id) {
                var col = next[ch.c] ?? [:]
                if ch.del != nil { col[ch.id] = nil } else if let v = ch.v { col[ch.id] = v }
                next[ch.c] = col
            }
            if next != cols { cols = next }
            rev = reply.rev; lastSync = Date(); state = .idle; save()
        } catch let e as API.Failure where e.status == 401 {
            Keychain.set("token", nil); self.token = nil; state = .error("Вход устарел — войдите заново")
        } catch let e as API.Failure {
            state = .error(e.message)
        } catch {
            state = .offline
        }
    }

    // кэш на устройстве
    private func load() {
        guard let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(Cache.self, from: d) else { return }
        rev = c.rev; cols = c.cols; pending = c.pending
    }
    private func save() {
        let c = Cache(rev: rev, cols: cols, pending: pending)
        if let d = try? JSONEncoder().encode(c) { try? d.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
}

// MARK: - Чертежи: скачиваются один раз и дальше открываются с устройства

enum FileCache {
    struct NotOnServer: LocalizedError {
        var errorDescription: String? { "Этот файл загружен только на компьютере. Положите его в папку на Google Диске, чтобы открыть на iPhone и iPad." }
    }

    private static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("drawings", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func local(_ id: String) -> URL { dir.appendingPathComponent(id.replacingOccurrences(of: ":", with: "_") + ".pdf") }
    static func has(_ id: String) -> Bool { FileManager.default.fileExists(atPath: local(id).path) }

    static func get(_ id: String, token: String?) async throws -> URL {
        let url = local(id)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard id.hasPrefix("gd:") else { throw NotOnServer() }
        let data = try await API.request("api/center/gdrive/file/" + String(id.dropFirst(3)), token: token, timeout: 120)
        try data.write(to: url, options: .atomic)
        return url
    }
    static func clear() { try? FileManager.default.removeItem(at: dir) }
    static var sizeMB: Double {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return Double(files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }) / 1_048_576
    }
}

// MARK: - Общие элементы

extension Color {
    static let pto = Color(red: 0.36, green: 0.42, blue: 0.94)
}

struct Badge: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }
}

struct SyncPill: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    private var color: Color {
        switch store.state {
        case .idle: return store.pendingCount > 0 ? .orange : .green
        case .syncing: return .blue
        case .offline: return .orange
        case .error: return .red
        }
    }
    private var text: String {
        switch store.state {
        case .idle: return store.pendingCount > 0 ? "Ждёт отправки: \(store.pendingCount)" : "Сохранено на сервере"
        case .syncing: return "Синхронизация…"
        case .offline: return "Нет связи — всё сохранится позже"
        case .error(let m): return m
        }
    }
}
