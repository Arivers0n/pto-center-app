import Foundation

// Схемы с Google Диска: сервер отдаёт список файлов (путь + id), закрытия и схемы разбираются по названиям папок, как в веб-версии.
// Таблицы xlsx к схемам (tbl) здесь не читаются — они подтянутся из веб-версии.

private struct KsDriveFile: Decodable { let id: String; let path: String }
private struct KsDriveTree: Decodable { let files: [KsDriveFile] }
private struct KsDriveStatus: Decodable { let hasKey: Bool?; let folder: String? }

struct KsDriveResult { let addedSchemes: Int; let addedClosings: Int; let message: String }

private struct KsParsedClosing {
    var no: Int; var date: String; var status: String; var shop: String; var votes: [String: Int] = [:]
}
private struct KsGroup { var ck: String?; var gdir: String; var shop: String; var pdf: [KsDriveFile] = []; var dwg: [KsDriveFile] = [] }
private struct KsParsedScheme {
    var ck: String?; var shop: String; var title: String; var group: String; var sys: [String]; var axes: String
    var pdf: KsDriveFile?; var signed: KsDriveFile?; var dwg: [String]; var src: String
}

enum KsDrive {
    // MARK: разбор названий

    private static func sub(_ s: String, _ p: String, _ r: String) -> String {
        s.replacingOccurrences(of: p, with: r, options: [.regularExpression, .caseInsensitive])
    }
    private static func groups(_ s: String, _ p: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func clean(_ s: String) -> String {
        var t = s
        let steps: [(String, String)] = [
            ("\\.(pdf|dwg|xlsx?)$", ""), ("^\\s*\\d{1,2}\\s*_\\s*", ""), ("\\(\\s*КС\\s*-?\\s*[\\d.]+\\s*\\)\\.?", ""),
            ("И\\.\\s?С\\.\\s*", ""), ("\\(\\s*Аппаратный\\s*\\)\\.?", ""), ("\\bподписан[а-я]*\\b", ""),
            ("^\\s*Исполнительн[а-я]*\\s+схем[а-я]*\\s*", ""), ("^\\s*сист\\.?\\s*", ""), ("\\s+", " "),
            ("^[\\s.,;:\\-–—]+|[\\s.,;:\\-–—]+$", "")
        ]
        for (p, r) in steps { t = sub(t, p, r) }
        return t
    }

    static func systems(_ text: String) -> [String] {
        let vd = text.lowercased().contains("вд")
        var out: [String] = []
        let p = "(?<![А-Яа-яA-Za-z])(В\\s?1[.\\-]1|В\\s?1|Т\\s?3|Т\\s?4|К\\s?[123]|ОВ\\s?\\d?|КМ\\s?\\d?)(?![0-9])"
        if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var k = ns.substring(with: m.range(at: 1)).filter { !$0.isWhitespace }.uppercased()
                k = k.replacingOccurrences(of: "В1-1", with: "В1.1")
                if vd && (k == "В1" || k == "Т3") { k += "вд" }
                if !out.contains(k) { out.append(k) }
            }
        }
        let low = text.lowercased()
        if low.contains("изоляц") && !out.contains("Изоляция") { out.append("Изоляция") }
        if low.contains("опор") && !out.contains("КМ") && !out.contains("Опоры") { out.append("Опоры") }
        return out
    }

    static func axes(_ text: String) -> String {
        let p = "(?:в\\s+осях|оси)\\s*([^()]+?)(?=\\s*\\(|\\)|$|\\s+отм|,\\s*отм)"
        guard let g = groups(text, p), g.count > 1 else { return "" }
        return sub(g[1], "[.,;\\s]+$", "").trimmingCharacters(in: .whitespaces)
    }

    private static let stop: Set<String> = ["сист", "в", "осях", "оси", "и", "с", "по", "аппаратный", "подписан", "кс", "ис", "схема", "исполнительная", "на", "от"]

    private static func tokens(_ text: String) -> Set<String> {
        var t = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        t = sub(t, "подписан[а-я]*", "")
        t = sub(t, "(^|[^а-яa-z])([втк])\\s+(\\d)", "$1$2$3")
        t = sub(t, "[^а-яa-z0-9]+", " ")
        var out = Set<String>()
        for w in t.split(separator: " ").map(String.init) where !w.isEmpty && !stop.contains(w) {
            let isWord = w.count >= 6 && w.allSatisfy { ("а"..."я").contains($0) }
            out.insert(isWord ? String(w.prefix(5)) : w)
        }
        return out
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let x = tokens(a), y = tokens(b)
        if x.isEmpty || y.isEmpty { return 0 }
        let n = x.intersection(y).count
        return Double(n) / Double(x.count + y.count - n)
    }

    private static func parseClosing(_ seg: String) -> (no: Int, date: String, status: String)? {
        guard let g = groups(seg, "закрыти[ея]\\s*№?\\s*(\\d+)"), let no = Int(g[1]) else { return nil }
        var date = ""
        if let d = groups(seg, "от\\s*(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2,4})"), let dd = Int(d[1]), let mm = Int(d[2]), var yy = Int(d[3]) {
            if d[3].count == 2 { yy += 2000 }
            date = String(format: "%04d-%02d-%02d", yy, mm, dd)
        }
        var status = "work"
        if groups(seg, "в\\s*работе|актуал") != nil { status = "work" }
        else if groups(seg, "остат") != nil { status = "rest" }
        else if !date.isEmpty { status = "closed" }
        return (no, date, status)
    }

    private static func projectGuess(_ path: String, _ projects: [String]) -> String {
        let p = path.lowercased().replacingOccurrences(of: "ё", with: "е")
        for n in projects {
            let k = n.lowercased().replacingOccurrences(of: "ё", with: "е")
            let stem = k.count > 5 ? String(k.prefix(max(4, k.count - 3))) : k
            if !stem.isEmpty && p.contains(stem) { return n }
        }
        return ""
    }

    // MARK: разбор дерева

    private static func parse(_ files: [KsDriveFile], projects: [String]) -> (cls: [(key: String, c: KsParsedClosing)], schemes: [KsParsedScheme]) {
        var clsKeys: [String] = []
        var cls: [String: KsParsedClosing] = [:]
        var groupKeys: [String] = []
        var grp: [String: KsGroup] = [:]
        var signed: [String: [KsDriveFile]] = [:]
        let skipDirs: Set<String> = ["old", "00_old", "архив"]

        for e in files {
            let segs = e.path.split(separator: "/").map(String.init)
            guard let name = segs.last else { continue }
            let dirs = Array(segs.dropLast())
            let ext = (name as NSString).pathExtension.lowercased()
            guard ["pdf", "dwg", "xlsx"].contains(ext), !name.hasPrefix("~$") else { continue }
            let ci = dirs.firstIndex { parseClosing($0) != nil }
            let skipped = dirs.enumerated().contains { (i, d) in
                skipDirs.contains(d.lowercased()) || groups(d, "^в работе на") != nil || (ci != nil && i > ci! && d == "1")
            }
            if skipped { continue }
            let shop = projectGuess(e.path, projects)
            var ck: String?
            if let ci, let c = parseClosing(dirs[ci]) {
                let key = dirs[0...ci].joined(separator: "/")
                ck = key
                if cls[key] == nil {
                    clsKeys.append(key)
                    cls[key] = KsParsedClosing(no: c.no, date: c.date, status: c.status, shop: projectGuess(dirs[ci], projects))
                }
                if !shop.isEmpty { cls[key]?.votes[shop, default: 0] += 1 }
            }
            let rest: [String] = ci != nil ? Array(dirs[(ci! + 1)...]) : dirs
            let isSigned = rest.contains { groups($0, "подпис") != nil } || (name.lowercased().contains("подписан") && ext == "pdf")
            if isSigned {
                if ext == "pdf" { signed[ck ?? "", default: []].append(e) }
                continue
            }
            let gdir = ci != nil ? (rest.first ?? "") : (dirs.last ?? "")
            let gk = (ck ?? "") + "|" + gdir
            if grp[gk] == nil { groupKeys.append(gk); grp[gk] = KsGroup(ck: ck, gdir: gdir, shop: shop) }
            if ext == "pdf" { grp[gk]?.pdf.append(e) } else if ext == "dwg" { grp[gk]?.dwg.append(e) }
        }
        for k in clsKeys {
            if cls[k]?.shop.isEmpty == true, let top = cls[k]?.votes.max(by: { $0.value < $1.value }) { cls[k]?.shop = top.key }
        }
        func clShop(_ k: String?) -> String { k.flatMap { cls[$0]?.shop } ?? "" }

        var schemes: [KsParsedScheme] = []
        for gk in groupKeys {
            guard var g = grp[gk], !g.pdf.isEmpty else { continue }
            g.shop = clShop(g.ck).isEmpty ? g.shop : clShop(g.ck)
            let one = g.pdf.count == 1
            for p in g.pdf {
                let pn = p.path.split(separator: "/").last.map(String.init) ?? p.path
                let title = one && !g.gdir.isEmpty ? clean(g.gdir) : clean(pn)
                let ax = axes(title).isEmpty ? axes(g.gdir) : axes(title)
                schemes.append(KsParsedScheme(ck: g.ck, shop: g.shop, title: title, group: one ? "" : clean(g.gdir),
                                              sys: systems(title + " " + (one ? "" : g.gdir)), axes: ax,
                                              pdf: p, signed: nil, dwg: g.dwg.map { $0.path }, src: p.path))
            }
        }
        for (key, list) in signed {
            let ck: String? = key.isEmpty ? nil : key
            for e in list {
                let last = e.path.split(separator: "/").last.map(String.init) ?? e.path
                let t = clean(last)
                var best: Int?
                var bs = 0.0
                for (i, s) in schemes.enumerated() where s.ck == ck && s.signed == nil {
                    let v = similarity(t, s.title)
                    if v > bs { bs = v; best = i }
                }
                if let b = best, bs >= 0.5 {
                    schemes[b].signed = e
                } else {
                    let shop = clShop(ck).isEmpty ? projectGuess(e.path, projects) : clShop(ck)
                    schemes.append(KsParsedScheme(ck: ck, shop: shop, title: t, group: "Подписанные", sys: systems(t), axes: axes(t),
                                                  pdf: nil, signed: e, dwg: [], src: e.path))
                }
            }
        }
        return (clsKeys.compactMap { k in cls[k].map { (key: k, c: $0) } }, schemes)
    }

    // MARK: запись в хранилище

    @MainActor
    static func sync(store: Store) async throws -> KsDriveResult {
        let sdata = try await API.request("api/center/gdrive/status", token: store.token)
        let st = try JSONDecoder().decode(KsDriveStatus.self, from: sdata)
        guard st.hasKey == true, !(st.folder ?? "").isEmpty else {
            throw API.Failure(message: "Google Диск не подключён. Подключите ключ и папку в настройках ПТО-центра на компьютере.", status: 0)
        }
        let tdata = try await API.request("api/center/gdrive/tree?refresh=1", token: store.token, timeout: 180)
        let tree = try JSONDecoder().decode(KsDriveTree.self, from: tdata)
        let projects = ksProjects(store.cfg)
        let parsed = parse(tree.files, projects: projects)
        return await apply(parsed, store: store, files: tree.files.count)
    }

    @MainActor
    private static func apply(_ p: (cls: [(key: String, c: KsParsedClosing)], schemes: [KsParsedScheme]), store: Store, files: Int) async -> KsDriveResult {
        var map: [String: String] = [:]
        var addC = 0, addS = 0, skip = 0
        for item in p.cls {
            let c = item.c
            let existing = store.list("closings").first { x in
                Int(x["no"].num ?? -1) == c.no && (x["shop"].str == c.shop || x["shop"].str.isEmpty || c.shop.isEmpty)
            }
            if var ex = existing {
                var changed = false
                if ex["date"].str.isEmpty && !c.date.isEmpty { ex.v["date"] = JSON.s(c.date); changed = true }
                if ex["shop"].str.isEmpty && !c.shop.isEmpty { ex.v["shop"] = JSON.s(c.shop); changed = true }
                if changed { store.put("closings", ex) }
                map[item.key] = ex.id
            } else {
                let v: [String: JSON] = ["no": .n(Double(c.no)), "date": .s(c.date), "shop": .s(c.shop), "status": .s(c.status), "note": .s("")]
                let r = Rec(id: Fmt.uid(), v: .o(v))
                store.put("closings", r)
                map[item.key] = r.id
                addC += 1
            }
        }
        var done = 0
        for s in p.schemes {
            done += 1
            if done % 15 == 0 { await Task.yield() }
            let cl: String? = s.ck.flatMap { map[$0] }
            let norm = { (t: String) -> String in clean(t).lowercased() }
            let pdfId = s.pdf.map { "gd:" + $0.id }
            let sigId = s.signed.map { "gd:" + $0.id }
            let ex = store.list("schemes").first { x in
                (x["closing"].str.isEmpty ? nil : x["closing"].str) == cl && norm(x["title"].str) == norm(s.title)
            }
            if var x = ex {
                var ch = false
                if let pid = pdfId, x["pdf"].str != pid {
                    x.v["pdf"] = JSON.s(pid); x.v["pdfName"] = JSON.s(s.pdf?.path.split(separator: "/").last.map(String.init) ?? ""); ch = true
                }
                if let sid = sigId, x["signed"].str != sid {
                    let hadSigned = !x["signed"].str.isEmpty
                    x.v["signed"] = JSON.s(sid)
                    x.v["sigName"] = JSON.s(s.signed?.path.split(separator: "/").last.map(String.init) ?? "")
                    if !hadSigned { x.v["status"] = JSON.s("signed") }
                    ch = true
                }
                if ch { store.put("schemes", x); addS += 1 } else { skip += 1 }
                continue
            }
            let closing = cl.flatMap { store.get("closings", $0) }
            let status = sigId != nil ? "signed" : ((closing != nil && closing?["status"].str != "work") ? "review" : "draft")
            let v: [String: JSON] = [
                "closing": cl.map { JSON.s($0) } ?? .null,
                "shop": .s(s.shop.isEmpty ? (closing?["shop"].str ?? "") : s.shop),
                "title": .s(s.title), "group": .s(s.group), "sys": .a(s.sys.map { JSON.s($0) }), "axes": .s(s.axes),
                "status": .s(status),
                "pdf": pdfId.map { JSON.s($0) } ?? .null,
                "pdfName": .s(s.pdf?.path.split(separator: "/").last.map(String.init) ?? ""),
                "signed": sigId.map { JSON.s($0) } ?? .null,
                "sigName": .s(s.signed?.path.split(separator: "/").last.map(String.init) ?? ""),
                "dwg": .a(s.dwg.map { JSON.s($0) }), "tbl": .a([]), "pins": .a([]), "note": .s(""), "src": .s(s.src), "added": .s(Fmt.today)
            ]
            store.put("schemes", Rec(id: Fmt.uid(), v: .o(v)))
            addS += 1
        }
        let msg: String
        if addS == 0 && addC == 0 { msg = "Новых схем на Диске нет. Просмотрено файлов: \(files)." }
        else { msg = "С Google Диска: схем \(addS)" + (addC > 0 ? ", закрытий \(addC)" : "") + (skip > 0 ? ". Уже были: \(skip)" : "") + "." }
        return KsDriveResult(addedSchemes: addS, addedClosings: addC, message: msg)
    }
}
