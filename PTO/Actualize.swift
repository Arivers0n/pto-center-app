import SwiftUI
import PDFKit

private let rqActCols = ["requests", "closings", "schemes", "notes", "tasks", "contacts", "journal", "issues", "joints", "mats", "expenses", "snips"]
private let rqActShown = 200
private let rqActDeepLimit = 80
private let rqActWidth: CGFloat = 720

// MARK: - Найденное и снимок данных

struct RqFinding: Identifiable {
    let id: String
    let group: String
    let text: String
    var on = false
    var fix: (@MainActor (Store) -> Void)?
}

struct RqSnapshot: Codable {
    let at: Date
    let cols: [String: [String: JSON]]
    let reqSecs: JSON?
}

enum RqSnapshotFile {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pto-before-act.json")
    }
    static func load() -> RqSnapshot? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RqSnapshot.self, from: d)
    }
    static func save(_ s: RqSnapshot) throws { try JSONEncoder().encode(s).write(to: url, options: .atomic) }
    static func clear() { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Поиск (actFindReq, actFindDup, actFindIs)

@MainActor
enum RqAct {
    static func patch(_ s: Store, _ col: String, _ id: String, _ f: (inout JSON) -> Void) {
        guard var r = s.get(col, id) else { return }
        f(&r.v)
        s.put(col, r)
    }

    private static func sig(_ r: Rec) -> String {
        r["items"].arr.filter { !$0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Rq.nm($0["name"].str) + "|" + String($0["qty"].num ?? 0) }.sorted().joined(separator: ";")
    }
    private static func reqName(_ r: Rec) -> String { "№" + Rq.title(r.v) }
    private static func byDate(_ a: Rec, _ b: Rec) -> Bool {
        let da = a["date"].str, db = b["date"].str
        return da == db ? a.id < b.id : da < db
    }

    /// Раздел по тексту (FX.guess в вебе)
    private static func guessSection(_ place: String, _ work: String, _ shop: String) -> String {
        let t = (place + " " + work).lowercased(), sh = shop.lowercased()
        if t.contains("пожарн") || t.contains("-пт") { return "5" }
        if t.contains("ов2") || t.contains("вентиляц") { return sh.contains("аппарат") ? "6" : "4" }
        if t.contains("ов1") || t.contains("ов 1") { return "3" }
        return sh.contains("аппарат") ? "1" : "2"
    }

    static func findReq(_ store: Store) -> [RqFinding] {
        let all = store.list("requests").sorted(by: byDate)
        let secs = store.reqSections
        let secIds = Set(secs.map(\.id))
        var out: [RqFinding] = []
        var bySig: [String: Rec] = [:]
        for r in all where !r["sec"].str.isEmpty { bySig[r["no"].str + "#" + sig(r)] = r }

        for r in all where sig(r).isEmpty {
            let id = r.id
            out.append(RqFinding(id: "e" + id, group: "Пустые заявки", text: "\(reqName(r)) от \(Fmt.show(r["date"].str)): нет ни одной позиции", on: true,
                                 fix: { $0.delete("requests", id) }))
        }
        for r in all where r["sec"].str.isEmpty && !sig(r).isEmpty {
            guard let tw = bySig[r["no"].str + "#" + sig(r)] else { continue }
            let id = r.id
            out.append(RqFinding(id: "c" + id, group: "Старые копии",
                                 text: "№\(r["no"].str) от \(Fmt.show(r["date"].str)) без раздела: такая же есть в «\(store.secName(tw["sec"].str))» (\(reqName(tw)))", on: true,
                                 fix: { $0.delete("requests", id) }))
        }
        var seen = Set<String>()
        for r in all where !r["sec"].str.isEmpty && !sig(r).isEmpty {
            let k = r["sec"].str + "#" + r["no"].str + "#" + sig(r)
            if seen.contains(k) {
                let id = r.id
                out.append(RqFinding(id: "d" + id, group: "Двойные заявки", text: "\(reqName(r)) в «\(store.secName(r["sec"].str))» записана дважды", on: true,
                                     fix: { $0.delete("requests", id) }))
            } else { seen.insert(k) }
        }
        out += findLost(store, all, secs, secIds)
        for r in all where r["sec"].str.isEmpty && !sig(r).isEmpty && bySig[r["no"].str + "#" + sig(r)] == nil {
            let g = guessSection(Rq.place(r.v), r["work"].str, r["shop"].str)
            guard let s = secs.first(where: { $0.id == g }) else { continue }
            let id = r.id
            out.append(RqFinding(id: "s" + id, group: "Без раздела", text: "№\(r["no"].str) от \(Fmt.show(r["date"].str)): похоже на «\(s.name)»",
                                 fix: { st in patch(st, "requests", id) { $0["sec"] = .s(s.id) } }))
        }
        var nos: [String: [Rec]] = [:]
        for r in all where !r["sec"].str.isEmpty && !sig(r).isEmpty { nos[r["sec"].str + "#" + r["no"].str, default: []].append(r) }
        for k in nos.keys.sorted() {
            guard let l = nos[k], l.count > 1, Set(l.map(sig)).count > 1 else { continue }
            out.append(RqFinding(id: "n" + k, group: "Проверить вручную",
                                 text: "В «\(store.secName(l[0]["sec"].str))» номер \(l[0]["no"].str) у \(l.count) разных заявок"))
        }
        return out
    }

    private static func findLost(_ store: Store, _ all: [Rec], _ secs: [ReqSection], _ secIds: Set<String>) -> [RqFinding] {
        var lost: [String: [String]] = [:]
        for r in all where !r["sec"].str.isEmpty && !secIds.contains(r["sec"].str) { lost[r["sec"].str, default: []].append(r.id) }
        return lost.keys.sorted().map { sid -> RqFinding in
            let ids = lost[sid] ?? []
            let same = secs.first { Rq.nm($0.name) == Rq.nm(sid) }?.id
            let what = same != nil ? "перенести в «\(store.secName(same ?? ""))»" : "создать вкладку «\(sid)»"
            return RqFinding(id: "l" + sid, group: "Заявки не видны во вкладках",
                             text: "\(ids.count) заявок с разделом «\(sid)», которого нет во вкладках: \(what)", on: true,
                             fix: { st in
                                 let target = same ?? addSection(st, name: sid)
                                 for id in ids { patch(st, "requests", id) { $0["sec"] = .s(target) } }
                             })
        }
    }

    /// Новая вкладка заявок; возвращает её номер
    private static func addSection(_ st: Store, name: String) -> String {
        var list = st.cfg["reqSecs"].arr
        if list.isEmpty {
            list = st.reqSections.map { JSON.o(["id": .s($0.id), "name": .s($0.name), "full": .s($0.full)]) }
        }
        let next = String(Int(list.compactMap { $0["id"].num }.max() ?? 0) + 1)
        list.append(.o(["id": .s(next), "name": .s(name), "full": .s(name)]))
        var c = st.cfg
        c["reqSecs"] = .a(list)
        st.setKV("cfg", c)
        return next
    }

    static func findDup(_ store: Store) -> [RqFinding] {
        let names: [(String, String)] = [("notes", "Заметки"), ("tasks", "Задачи"), ("contacts", "Контакты"), ("journal", "Журнал прораба"),
                                         ("issues", "Замечания"), ("joints", "Стыки"), ("mats", "Материалы"), ("expenses", "Расходы"), ("snips", "Шпаргалки")]
        var out: [RqFinding] = []
        for (col, title) in names {
            var seen = Set<JSON>()
            for r in store.list(col).sorted(by: { $0.id < $1.id }) {
                var o = r.v.obj
                o["id"] = nil
                if seen.insert(JSON.o(o)).inserted { continue }
                let label = ["title", "text", "name", "no", "date"].map { r[$0].str }.first { !$0.isEmpty } ?? "запись"
                let id = r.id
                out.append(RqFinding(id: "u" + col + id, group: "Повторы: " + title, text: String(label.prefix(80)) + " — такая же запись уже есть", on: true,
                                     fix: { $0.delete(col, id) }))
            }
        }
        return out
    }

    // MARK: Схемы и закрытия

    private static func closingName(_ c: Rec?) -> String {
        guard let c else { return "Не распределены" }
        return "Закрытие №" + c["no"].str + (c["date"].str.isEmpty ? "" : " от " + Fmt.show(c["date"].str))
    }
    private static func projects(_ store: Store) -> [String] {
        var seen = Set<String>()
        let l = store.shops.map { $0.replacingOccurrences(of: " цех", with: "", options: [.caseInsensitive, .anchored, .backwards]).trimmingCharacters(in: .whitespaces) }
        return l.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private static func projGuess(_ store: Store, _ path: String) -> String {
        let p = path.lowercased().replacingOccurrences(of: "ё", with: "е")
        for n in projects(store) {
            let k = n.lowercased().replacingOccurrences(of: "ё", with: "е")
            let stem = k.count > 5 ? String(k.prefix(max(4, k.count - 3))) : k
            if !stem.isEmpty && p.contains(stem) { return n }
        }
        return ""
    }
    static func pdfPages(_ store: Store, _ id: String) async -> Int {
        guard !id.isEmpty, let url = try? await FileCache.get(id, token: store.token), let d = PDFDocument(url: url) else { return 0 }
        return d.pageCount
    }

    static func findSchemes(_ store: Store, deep: Bool, step: (String) -> Void) async -> [RqFinding] {
        let closings = store.list("closings").sorted { $0.id < $1.id }
        let schemes = store.list("schemes").sorted { $0.id < $1.id }
        var out = noProject(store, closings, schemes)
        out += doubles(schemes, closings)
        out += await packages(store, closings, schemes, deep: deep, step: step)
        out += statuses(schemes)
        if deep { out += await differences(store, closings, schemes, step: step) }
        return out
    }

    private static func noProject(_ store: Store, _ closings: [Rec], _ schemes: [Rec]) -> [RqFinding] {
        closings.filter { $0["shop"].str.isEmpty }.map { c -> RqFinding in
            let mine = schemes.filter { $0["closing"].str == c.id }
            let g = projGuess(store, mine.map { $0["group"].str.isEmpty ? $0["title"].str : $0["group"].str }.joined(separator: " "))
            let id = c.id, ids = mine.map(\.id)
            let t = "Закрытие №\(c["no"].str)" + (c["date"].str.isEmpty ? "" : " от " + Fmt.show(c["date"].str)) + " не привязано к проекту" + (g.isEmpty ? "" : ": похоже «\(g)»")
            var fixer: (@MainActor (Store) -> Void)?
            if !g.isEmpty {
                fixer = { st in
                    patch(st, "closings", id) { $0["shop"] = .s(g) }
                    for sid in ids { patch(st, "schemes", sid) { $0["shop"] = .s(g) } }
                }
            }
            return RqFinding(id: "p" + id, group: "Закрытия без проекта", text: t, on: !g.isEmpty, fix: fixer)
        }
    }

    private static func doubles(_ schemes: [Rec], _ closings: [Rec]) -> [RqFinding] {
        var first: [String: Rec] = [:]
        var out: [RqFinding] = []
        for s in schemes {
            let key = s["closing"].str + "#" + Rq.nm(s["title"].str)
            guard let a = first[key] else { first[key] = s; continue }
            let sid = s.id, aid = a.id
            let c = closings.first { $0.id == s["closing"].str }
            out.append(RqFinding(id: "ds" + sid, group: "Двойные схемы",
                                 text: "«\(s["title"].str)» дважды в \(closingName(c)): оставить одну, файлы и замечания объединить", on: true,
                                 fix: { st in
                                     guard let dup = st.get("schemes", sid), var keep = st.get("schemes", aid) else { return }
                                     if !dup["signed"].str.isEmpty && keep["signed"].str.isEmpty { keep.v["signed"] = dup["signed"] }
                                     if !dup["pdf"].str.isEmpty && keep["pdf"].str.isEmpty { keep.v["pdf"] = dup["pdf"] }
                                     keep.v["pins"] = .a(keep["pins"].arr + dup["pins"].arr)
                                     st.put("schemes", keep)
                                     st.delete("schemes", sid)
                                 }))
        }
        return out
    }

    /// Подписанный файл может быть пакетом схем, а чистовики — отдельными файлами
    private static func packages(_ store: Store, _ closings: [Rec], _ schemes: [Rec], deep: Bool, step: (String) -> Void) async -> [RqFinding] {
        var out: [RqFinding] = []
        let pkgs = schemes.filter { !$0["signed"].str.isEmpty && $0["pdf"].str.isEmpty }
        for c in closings where c["status"].str == "closed" {
            let mine = schemes.filter { $0["closing"].str == c.id }
            let noSig = mine.filter { !$0["pdf"].str.isEmpty && $0["signed"].str.isEmpty }
            if noSig.isEmpty { continue }
            let pk = pkgs.filter { $0["closing"].str == c.id }
            let name = closingName(c)
            if pk.isEmpty {
                let list = noSig.prefix(4).map { "«\($0["title"].str)»" }.joined(separator: ", ")
                let more = noSig.count > 4 ? " и ещё \(noSig.count - 4)" : ""
                out.append(RqFinding(id: "ns" + c.id, group: "Нет подписанных", text: "\(name) закрыто, но у \(noSig.count) схем нет подписанной копии: \(list)\(more)"))
                continue
            }
            var pages = 0
            if deep {
                step("Листаю подписанный пакет: " + name)
                for p in pk { pages += await pdfPages(store, p["signed"].str) }
            }
            let covers = deep && pages >= noSig.count
            let titles = pk.map { "«\($0["title"].str)»" }.joined(separator: ", ")
            let tail = covers ? "Отметить чистовики подписанными в пакете." : (deep ? "Листов в пакете меньше, чем схем: проверьте пакет." : "Нажмите «Сверить файлы схем», чтобы посчитать листы.")
            let text = "\(name): у \(noSig.count) чистовиков нет отдельной подписанной копии, есть подписанный пакет \(titles)" + (deep ? " (\(pages) лист.)" : "") + ". " + tail
            let ids = noSig.map(\.id), file = pk[0]["signed"].str
            var fixer: (@MainActor (Store) -> Void)?
            if covers {
                fixer = { st in
                    for id in ids { patch(st, "schemes", id) { $0["signed"] = .s(file); $0["sigPkg"] = .b(true); $0["status"] = .s("signed") } }
                }
            }
            out.append(RqFinding(id: "pk" + c.id, group: "Подписаны пакетом", text: text, on: covers, fix: fixer))
        }
        return out
    }

    private static func statuses(_ schemes: [Rec]) -> [RqFinding] {
        var out: [RqFinding] = []
        for s in schemes {
            let id = s.id, title = s["title"].str, st = s["status"].str
            if st == "signed" && s["signed"].str.isEmpty {
                out.append(RqFinding(id: "st" + id, group: "Статус не совпадает с файлами",
                                     text: "«\(title)» отмечена подписанной, а подписанного файла нет: вернуть «На подписи»",
                                     fix: { patch($0, "schemes", id) { $0["status"] = .s("review") } }))
            }
            if !s["signed"].str.isEmpty && !s["pdf"].str.isEmpty && st != "signed" {
                let label = (isStatus[st] ?? isStatus["draft"] ?? ("Черновик", Color.secondary)).0
                out.append(RqFinding(id: "st2" + id, group: "Статус не совпадает с файлами",
                                     text: "«\(title)»: подписанная копия есть, а статус «\(label)»: отметить «Подписана»", on: true,
                                     fix: { patch($0, "schemes", id) { $0["status"] = .s("signed") } }))
            }
        }
        return out
    }

    private static func differences(_ store: Store, _ closings: [Rec], _ schemes: [Rec], step: (String) -> Void) async -> [RqFinding] {
        let l = schemes.filter { !$0["pdf"].str.isEmpty && !$0["signed"].str.isEmpty && !($0["sigPkg"]?.bool ?? false) && $0["pdf"].str != $0["signed"].str }
        var out: [RqFinding] = []
        for (n, s) in l.prefix(rqActDeepLimit).enumerated() {
            step("Сравниваю чистовики с подписанными: \(n + 1) из \(min(l.count, rqActDeepLimit))")
            let a = await pdfPages(store, s["pdf"].str), b = await pdfPages(store, s["signed"].str)
            guard a > 0, b > 0, a != b else { continue }
            let c = closings.first { $0.id == s["closing"].str }
            out.append(RqFinding(id: "df" + s.id, group: "Отличия от подписанных",
                                 text: "«\(s["title"].str)» в \(closingName(c)): в чистовике \(a) лист., в подписанной \(b). Проверьте, та ли версия подписана"))
        }
        return out
    }

    // MARK: Снимок и возврат

    static func snapshot(_ store: Store) -> RqSnapshot {
        var cols: [String: [String: JSON]] = [:]
        for c in rqActCols { cols[c] = store.cols[c] ?? [:] }
        return RqSnapshot(at: Date(), cols: cols, reqSecs: store.cfg["reqSecs"])
    }

    static func restore(_ store: Store, _ snap: RqSnapshot) {
        for (col, saved) in snap.cols {
            for r in store.list(col) where saved[r.id] == nil { store.delete(col, r.id) }
            for (id, v) in saved where store.get(col, id)?.v != v { store.put(col, Rec(id: id, v: v)) }
        }
        if let secs = snap.reqSecs {
            var c = store.cfg
            c["reqSecs"] = secs
            store.setKV("cfg", c)
        }
    }
}

// MARK: - Окно «Актуализация данных»

struct ActualizeView: View {
    @EnvironmentObject var store: Store
    @State private var findings: [RqFinding] = []
    @State private var checked: [String: Bool] = [:]
    @State private var busy = true
    @State private var status = "Ищу лишнее и ошибки…"
    @State private var deepDone = false
    @State private var result: String?
    @State private var snap: RqSnapshot?
    @State private var askUndo = false

    private var groups: [String] {
        var seen = Set<String>()
        return findings.map(\.group).filter { seen.insert($0).inserted }
    }
    private func isOn(_ f: RqFinding) -> Bool { checked[f.id] ?? f.on }
    private var todo: [RqFinding] { findings.filter { $0.fix != nil && isOn($0) } }

    var body: some View {
        List {
            Section {
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
                if busy { HStack(spacing: 10) { ProgressView(); Text(status).font(.subheadline) } }
                if let r = result { Label(r, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(.green) }
            }
            if !busy { ForEach(groups, id: \.self) { g in groupSection(g) } }
            if !busy { actions }
        }
        .frame(maxWidth: rqActWidth)
        .frame(maxWidth: .infinity)
        .ptoScreen()
        .navigationTitle("Актуализация данных")
        .navigationBarTitleDisplayMode(.inline)
        .task { await run(deep: false) }
        .confirmationDialog("Вернуть данные, как они были до исправления?", isPresented: $askUndo, titleVisibility: .visible) {
            Button("Вернуть как было", role: .destructive) { undo() }
        }
    }

    private var summary: String {
        if busy { return "Проверяю заявки, закрытия и схемы." }
        if findings.isEmpty { return "Всё в порядке: дублей, пустых записей и расхождений не найдено." }
        return "Найдено: \(findings.count). Отмеченное будет исправлено. Перед исправлением приложение запоминает данные, и всё можно вернуть."
    }

    private func groupSection(_ g: String) -> some View {
        let items = findings.filter { $0.group == g }
        return Section {
            ForEach(items.prefix(rqActShown)) { f in row(f) }
            if items.count > rqActShown {
                Text("и ещё \(items.count - rqActShown) таких же — исправятся вместе с отмеченными").font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("\(g) · \(items.count)")
        }
    }

    @ViewBuilder private func row(_ f: RqFinding) -> some View {
        if f.fix != nil {
            Button { checked[f.id] = !isOn(f) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isOn(f) ? "checkmark.circle.fill" : "circle").foregroundStyle(isOn(f) ? Color.pto : Color.secondary)
                    Text(f.text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn(f) ? .isSelected : [])
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(f.text).font(.subheadline).multilineTextAlignment(.leading)
            }
        }
    }

    private var actions: some View {
        Section {
            if !findings.filter({ $0.fix != nil }).isEmpty {
                Button { apply() } label: { Label("Исправить отмеченное (\(todo.count))", systemImage: "wand.and.stars") }
                    .disabled(todo.isEmpty)
            }
            if !deepDone {
                Button { Task { await run(deep: true) } } label: { Label("Сверить файлы схем", systemImage: "doc.text.magnifyingglass") }
            }
            if let s = snap {
                Button(role: .destructive) { askUndo = true } label: { Label("Вернуть как было (\(stamp(s.at)))", systemImage: "arrow.uturn.backward") }
            }
        } footer: {
            if !deepDone { Text("Сверка открывает PDF: считает листы в подписанных пакетах и ищет отличия чистовиков от подписанных. Файлы скачиваются с сервера, это может занять минуту.") }
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }

    // MARK: Действия

    private func run(deep: Bool) async {
        busy = true
        status = deep ? "Открываю файлы схем, это может занять минуту…" : "Ищу лишнее и ошибки…"
        let req = RqAct.findReq(store)
        let isx = await RqAct.findSchemes(store, deep: deep) { text in status = text }
        let dup = RqAct.findDup(store)
        findings = req + isx + dup
        checked = [:]
        if deep { deepDone = true }
        snap = RqSnapshotFile.load()
        busy = false
    }

    private func apply() {
        let list = todo
        guard !list.isEmpty else { result = "Ничего не отмечено"; return }
        do { try RqSnapshotFile.save(RqAct.snapshot(store)) } catch {
            result = "Не удалось запомнить данные для отмены — исправление отменено"
            return
        }
        for f in list { f.fix?(store) }
        result = "Исправлено: \(list.count). Вернуть можно кнопкой «Вернуть как было»."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await run(deep: deepDone) }
    }

    private func undo() {
        guard let s = snap else { return }
        RqAct.restore(store, s)
        RqSnapshotFile.clear()
        result = "Данные возвращены"
        Task { await run(deep: deepDone) }
    }
}
