import SwiftUI
import UIKit

// MARK: - Числа и CSV для Excel (UTF-8 с BOM, разделитель «;»)

enum KsNum {
    private static func make(_ minF: Int, _ maxF: Int, grouping: Bool) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.minimumFractionDigits = minF
        f.maximumFractionDigits = maxF
        f.usesGroupingSeparator = grouping
        return f
    }
    private static let money = make(2, 2, grouping: true)
    private static let flat = make(0, 6, grouping: false)

    /// Деньги: «1 234,50»
    static func rub(_ v: Double) -> String { money.string(from: NSNumber(value: v)) ?? String(v) }
    /// Число без пробелов: «12,5»
    static func flatText(_ v: Double) -> String { flat.string(from: NSNumber(value: v)) ?? String(v) }
    /// Разбор введённого текста: запятая или точка, пробелы игнорируются
    static func parse(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
        return t.isEmpty ? nil : Double(t)
    }
}

enum KsCSV {
    private static func quote(_ s: String) -> String {
        guard s.contains(";") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func safeName(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "_")
    }
    /// Записывает файл во временную папку и возвращает адрес для «Поделиться»
    static func file(_ name: String, rows: [[String]]) -> URL? {
        let text = rows.map { $0.map(quote).joined(separator: ";") }.joined(separator: "\r\n")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName(name))
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// Кнопка «Поделиться» таблицей: файл готовится заранее и обновляется, когда меняются строки
struct KsCSVShare: View {
    let title: String
    let fileName: String
    let rows: [[String]]
    @State private var url: URL?
    var body: some View {
        Group {
            if let url {
                ShareLink(item: url) { Label(title, systemImage: "tablecells") }
            } else {
                Label(title, systemImage: "tablecells").foregroundStyle(.secondary)
            }
        }
        .task(id: rows) { url = KsCSV.file(fileName, rows: rows) }
    }
}

func ksPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m100 = n % 100, m10 = n % 10
    if m100 >= 11 && m100 <= 14 { return "\(n) \(many)" }
    if m10 == 1 { return "\(n) \(one)" }
    if m10 >= 2 && m10 <= 4 { return "\(n) \(few)" }
    return "\(n) \(many)"
}

// MARK: - Реквизиты актов (общие для всех закрытий, лежат в настройках cfg.ksReq)

enum KsReq {
    static let keys = ["investor", "customer", "contractor", "stroyka", "object", "contractNo", "contractDate",
                       "sdalPost", "sdalName", "prinPost", "prinName"]
    static let defaults: [String: String] = [
        "investor": "", "customer": "", "contractor": "ООО «СК «Артэк»",
        "stroyka": "Строительство молочного завода с производительностью 1150 т молока в сутки, р.п. Маслянино, Новосибирская область",
        "object": "", "contractNo": "28/11/2025-SZ", "contractDate": "2025-11-28",
        "sdalPost": "", "sdalName": "", "prinPost": "", "prinName": ""
    ]
    static func load(_ cfg: JSON) -> [String: String] {
        var out = defaults
        let saved = cfg["ksReq"]?.obj ?? [:]
        for k in keys { if let v = saved[k] { out[k] = v.str } }
        return out
    }
    static func save(_ store: Store, _ values: [String: String]) {
        var c = store.cfg
        var o: [String: JSON] = [:]
        for (k, v) in values { o[k] = JSON.s(v) }
        c["ksReq"] = JSON.o(o)
        store.setKV("cfg", c)
    }
}

// MARK: - Модель формы КС-2 / КС-3: одна на экран, CSV и PDF

struct KsSign: Equatable {
    let role: String
    let post: String
    let name: String
}

struct KsFormModel: Equatable {
    var form: String
    var okud: String
    var fileName: String
    var head: [[String]]
    var docHeader: [String]
    var docValues: [String]
    var title: [String]
    var columns: [String]
    var weights: [Double]
    var rightCols: [Int]
    var rows: [[String]]
    var totals: [[String]]
    var signs: [KsSign]

    private func flatNumbers(_ r: [String]) -> [String] {
        r.enumerated().map { (i, c) in rightCols.contains(i) ? c.filter { !$0.isWhitespace } : c }
    }

    /// Строки для Excel: шапка, таблица, подписи
    var csvRows: [[String]] {
        var out: [[String]] = [["Унифицированная форма № " + form], ["Утверждена постановлением Госкомстата России от 11.11.99 № 100"], ["Форма по ОКУД", okud], []]
        out += head
        out.append([])
        out.append(docHeader)
        out.append(docValues)
        out.append([])
        out += title.map { [$0] }
        out.append([])
        out.append(columns)
        out.append(columns.indices.map { String($0 + 1) })
        out += rows.map(flatNumbers)
        out += totals.map(flatNumbers)
        out.append([])
        for s in signs {
            out.append([s.role, s.post.isEmpty ? "______________________" : s.post, "__________", s.name.isEmpty ? "______________________" : s.name])
            out.append(["", "(должность)", "(подпись)", "(расшифровка подписи)"])
            out.append(["М. П."])
            out.append([])
        }
        return out
    }
}

enum KsForms {
    private static func head(_ r: [String: String]) -> [[String]] {
        func g(_ k: String) -> String { r[k] ?? "" }
        let object = g("object").isEmpty ? g("stroyka") : g("object")
        let date = g("contractDate").isEmpty ? "" : " от " + Fmt.show(g("contractDate"))
        return [["Инвестор", g("investor")], ["Заказчик (генподрядчик)", g("customer")], ["Подрядчик (субподрядчик)", g("contractor")],
                ["Стройка", g("stroyka")], ["Объект", object], ["Договор подряда (контракт)", "№ " + g("contractNo") + date]]
    }
    private static func docInfo(_ d: KsDoc) -> ([String], [String]) {
        (["Номер документа", "Дата составления", "Отчётный период с", "по"],
         [d.num, Fmt.show(d.dateDoc), Fmt.show(d.from), Fmt.show(d.to)])
    }
    private static func name(_ form: String, _ c: Rec) -> String {
        form + "_" + c["shop"].str + "_закрытие_" + c["no"].str
    }

    static func ks2(_ c: Rec, _ doc: KsDoc, _ req: [String: String], full: String) -> KsFormModel {
        let info = docInfo(doc)
        let named = doc.lines.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        var rows: [[String]] = []
        for (i, l) in named.enumerated() {
            rows.append([String(i + 1), l.sm, l.name, l.code, l.unit, l.qty, l.price.isEmpty ? "" : KsNum.rub(l.priceValue), l.sum > 0 ? KsNum.rub(l.sum) : ""])
        }
        let place = (full.isEmpty ? "" : full + " · ") + "Закрытие №" + c["no"].str
        return KsFormModel(
            form: "КС-2", okud: "0322005", fileName: name("КС-2", c), head: head(req),
            docHeader: info.0, docValues: info.1, title: ["АКТ", "О ПРИЁМКЕ ВЫПОЛНЕННЫХ РАБОТ", place],
            columns: ["№ п/п", "Поз. по смете", "Наименование работ", "Номер единичной расценки", "Ед. изм.", "Количество", "Цена за единицу, руб.", "Стоимость, руб."],
            weights: [0.55, 0.9, 3.6, 1.4, 0.8, 1.0, 1.3, 1.5], rightCols: [5, 6, 7],
            rows: rows, totals: [["Итого", "", "", "", "", "", "", KsNum.rub(doc.total)]],
            signs: [KsSign(role: "Сдал", post: req["sdalPost"] ?? "", name: req["sdalName"] ?? ""),
                    KsSign(role: "Принял", post: req["prinPost"] ?? "", name: req["prinName"] ?? "")])
    }

    static func ks3(_ c: Rec, _ doc: KsDoc, _ req: [String: String], full: String, prev: (all: Double, year: Double)) -> KsFormModel {
        let info = docInfo(doc)
        let tot = doc.total, vat = doc.vatPercent
        let all = prev.all + tot, year = prev.year + tot
        let object = (req["object"] ?? "").isEmpty ? (req["stroyka"] ?? "") : (req["object"] ?? "")
        let line = object + (full.isEmpty ? "" : " — " + full)
        func trio(_ a: Double, _ b: Double, _ p: Double) -> [String] { [KsNum.rub(a), KsNum.rub(b), KsNum.rub(p)] }
        let rows: [[String]] = [
            ["", "Всего работ и затрат, включаемых в стоимость работ", ""] + trio(all, year, tot),
            ["", "в том числе:", "", "", "", ""],
            ["1", line, ""] + trio(all, year, tot)
        ]
        let vatText = KsNum.flatText(vat)
        let totals: [[String]] = [
            ["", "Итого", ""] + trio(all, year, tot),
            ["", "Сумма НДС \(vatText) %", ""] + trio(all * vat / 100, year * vat / 100, tot * vat / 100),
            ["", "Всего с учётом НДС", ""] + trio(all * (1 + vat / 100), year * (1 + vat / 100), tot * (1 + vat / 100))
        ]
        return KsFormModel(
            form: "КС-3", okud: "0322001", fileName: name("КС-3", c), head: head(req),
            docHeader: info.0, docValues: info.1, title: ["СПРАВКА", "О СТОИМОСТИ ВЫПОЛНЕННЫХ РАБОТ И ЗАТРАТ"],
            columns: ["№ п/п", "Наименование пусковых комплексов, этапов, объектов, видов выполненных работ, оборудования, затрат", "Код",
                      "С начала проведения работ", "С начала года", "За отчётный период"],
            weights: [0.6, 4.0, 0.8, 1.6, 1.6, 1.6], rightCols: [3, 4, 5], rows: rows, totals: totals,
            signs: [KsSign(role: "Заказчик (генподрядчик)", post: req["prinPost"] ?? "", name: req["prinName"] ?? ""),
                    KsSign(role: "Подрядчик (субподрядчик)", post: req["sdalPost"] ?? "", name: req["sdalName"] ?? "")])
    }
}

// MARK: - PDF печатной формы (A4 альбомная)

private final class KsPen {
    let ctx: UIGraphicsPDFRendererContext
    let page: CGRect
    let margin: CGFloat = 28
    var y: CGFloat = 0
    init(ctx: UIGraphicsPDFRendererContext, page: CGRect) { self.ctx = ctx; self.page = page }

    var width: CGFloat { page.width - margin * 2 }
    func newPage() { ctx.beginPage(); y = margin }
    func ensure(_ h: CGFloat) -> Bool {
        guard y + h > page.height - margin else { return false }
        newPage()
        return true
    }
    func height(_ s: String, _ font: UIFont, _ w: CGFloat) -> CGFloat {
        let r = (s as NSString).boundingRect(with: CGSize(width: w, height: 10_000), options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
        return ceil(r.height)
    }
    func draw(_ s: String, _ rect: CGRect, _ font: UIFont, _ align: NSTextAlignment) {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: p, .foregroundColor: UIColor.black]
        (s as NSString).draw(in: rect, withAttributes: attrs)
    }
}

enum KsPDF {
    private static let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595)
    private static let body = UIFont.systemFont(ofSize: 8)
    private static let bold = UIFont.boldSystemFont(ofSize: 8)
    private static let big = UIFont.boldSystemFont(ofSize: 11)
    private static let pad: CGFloat = 3

    static func make(_ m: KsFormModel) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            let pen = KsPen(ctx: ctx, page: pageRect)
            pen.newPage()
            drawHeader(pen, m)
            drawTable(pen, m)
            drawSigns(pen, m)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(KsCSV.safeName(m.fileName) + ".pdf")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private static func line(_ pen: KsPen, _ s: String, font: UIFont, align: NSTextAlignment) {
        let h = pen.height(s, font, pen.width)
        _ = pen.ensure(h)
        pen.draw(s, CGRect(x: pen.margin, y: pen.y, width: pen.width, height: h), font, align)
        pen.y += h + 2
    }

    private static func drawHeader(_ pen: KsPen, _ m: KsFormModel) {
        line(pen, "Унифицированная форма № " + m.form, font: body, align: .right)
        line(pen, "Утверждена постановлением Госкомстата России от 11.11.99 № 100", font: body, align: .right)
        line(pen, "Форма по ОКУД  " + m.okud, font: bold, align: .right)
        pen.y += 6
        let labelW: CGFloat = 170
        for pair in m.head where pair.count == 2 {
            let value = pair[1]
            let h = max(pen.height(pair[0], bold, labelW), pen.height(value, body, pen.width - labelW - 6))
            _ = pen.ensure(h)
            pen.draw(pair[0], CGRect(x: pen.margin, y: pen.y, width: labelW, height: h), bold, .left)
            pen.draw(value, CGRect(x: pen.margin + labelW + 6, y: pen.y, width: pen.width - labelW - 6, height: h), body, .left)
            pen.y += h + 3
        }
        pen.y += 8
        let cw = min(pen.width / 4, 150)
        for (i, h) in m.docHeader.enumerated() {
            let r = CGRect(x: pen.margin + CGFloat(i) * cw, y: pen.y, width: cw, height: 24)
            pen.ctx.cgContext.stroke(r, width: 0.5)
            pen.draw(h, r.insetBy(dx: pad, dy: pad), body, .center)
        }
        pen.y += 24
        for (i, v) in m.docValues.enumerated() {
            let r = CGRect(x: pen.margin + CGFloat(i) * cw, y: pen.y, width: cw, height: 18)
            pen.ctx.cgContext.stroke(r, width: 0.5)
            pen.draw(v, r.insetBy(dx: pad, dy: pad), bold, .center)
        }
        pen.y += 28
        for t in m.title { line(pen, t, font: big, align: .center) }
        pen.y += 8
    }

    private static func widths(_ pen: KsPen, _ m: KsFormModel) -> [CGFloat] {
        let sum = m.weights.reduce(0, +)
        return m.weights.map { CGFloat($0 / sum) * pen.width }
    }

    private static func tableRow(_ pen: KsPen, _ m: KsFormModel, _ cells: [String], _ w: [CGFloat], font: UIFont, header: Bool) {
        var h: CGFloat = 0
        for (i, c) in cells.enumerated() where i < w.count { h = max(h, pen.height(c, font, w[i] - pad * 2)) }
        h += pad * 2
        if pen.ensure(h) && !header { tableRow(pen, m, m.columns, w, font: bold, header: true) }
        var x = pen.margin
        for (i, c) in cells.enumerated() where i < w.count {
            let r = CGRect(x: x, y: pen.y, width: w[i], height: h)
            pen.ctx.cgContext.stroke(r, width: 0.5)
            let align: NSTextAlignment = header ? .center : (m.rightCols.contains(i) ? .right : .left)
            pen.draw(c, r.insetBy(dx: pad, dy: pad), font, align)
            x += w[i]
        }
        pen.y += h
    }

    private static func drawTable(_ pen: KsPen, _ m: KsFormModel) {
        let w = widths(pen, m)
        tableRow(pen, m, m.columns, w, font: bold, header: true)
        tableRow(pen, m, m.columns.indices.map { String($0 + 1) }, w, font: body, header: true)
        for r in m.rows { tableRow(pen, m, r, w, font: body, header: false) }
        for r in m.totals { tableRow(pen, m, r, w, font: bold, header: false) }
        pen.y += 16
    }

    private static func drawSigns(_ pen: KsPen, _ m: KsFormModel) {
        for s in m.signs {
            _ = pen.ensure(50)
            let post = s.post.isEmpty ? "______________________" : s.post
            let name = s.name.isEmpty ? "______________________" : s.name
            pen.draw(s.role, CGRect(x: pen.margin, y: pen.y, width: 170, height: 12), bold, .left)
            pen.draw(post, CGRect(x: pen.margin + 180, y: pen.y, width: 200, height: 12), body, .left)
            pen.draw("__________", CGRect(x: pen.margin + 400, y: pen.y, width: 80, height: 12), body, .left)
            pen.draw(name, CGRect(x: pen.margin + 500, y: pen.y, width: 250, height: 12), body, .left)
            pen.y += 14
            pen.draw("(должность)", CGRect(x: pen.margin + 180, y: pen.y, width: 200, height: 10), UIFont.systemFont(ofSize: 6), .left)
            pen.draw("(подпись)", CGRect(x: pen.margin + 400, y: pen.y, width: 80, height: 10), UIFont.systemFont(ofSize: 6), .left)
            pen.draw("(расшифровка подписи)", CGRect(x: pen.margin + 500, y: pen.y, width: 250, height: 10), UIFont.systemFont(ofSize: 6), .left)
            pen.y += 12
            pen.draw("М. П.", CGRect(x: pen.margin, y: pen.y, width: 100, height: 12), body, .left)
            pen.y += 24
        }
    }
}

// MARK: - Форма на экране

struct KsFormView: View {
    let model: KsFormModel
    @State private var csv: URL?
    @State private var pdf: URL?
    private let unit: CGFloat = 76

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                shareRow
                header
                ScrollView(.horizontal, showsIndicators: true) { table.padding(.bottom, 4) }
                signs
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ptoScreen()
        .navigationTitle(model.form)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model) {
            csv = KsCSV.file(model.fileName + ".csv", rows: model.csvRows)
            pdf = KsPDF.make(model)
        }
    }

    private var shareRow: some View {
        HStack(spacing: 10) {
            if let csv { ShareLink(item: csv) { Label("Excel (CSV)", systemImage: "tablecells") }.buttonStyle(.borderedProminent) }
            if let pdf { ShareLink(item: pdf) { Label("PDF для печати", systemImage: "printer") }.buttonStyle(.bordered) }
            if csv == nil && pdf == nil { ProgressView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Унифицированная форма № \(model.form) · ОКУД \(model.okud)").font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(model.head.enumerated()), id: \.offset) { _, pair in
                if pair.count == 2 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pair[0]).font(.caption).foregroundStyle(.secondary)
                        Text(pair[1].isEmpty ? "—" : pair[1]).font(.subheadline)
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(Array(zip(model.docHeader, model.docValues).enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.0).font(.caption2).foregroundStyle(.secondary)
                        Text(p.1.isEmpty ? "—" : p.1).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .padding(.top, 4)
            ForEach(Array(model.title.enumerated()), id: \.offset) { i, t in
                Text(t).font(i < 2 ? .headline : .subheadline).frame(maxWidth: .infinity)
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            tableRow(model.columns, header: true)
            tableRow(model.columns.indices.map { String($0 + 1) }, header: true, small: true)
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, r in tableRow(r, header: false) }
            ForEach(Array(model.totals.enumerated()), id: \.offset) { _, r in tableRow(r, header: false, strong: true) }
        }
    }

    private func tableRow(_ cells: [String], header: Bool, small: Bool = false, strong: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                let w = CGFloat(i < model.weights.count ? model.weights[i] : 1) * unit
                let right = model.rightCols.contains(i) && !header
                Text(c)
                    .font(small ? .caption2 : (header || strong ? .caption.weight(.semibold) : .caption))
                    .monospacedDigit()
                    .multilineTextAlignment(header ? .center : (right ? .trailing : .leading))
                    .padding(6)
                    .frame(width: w, alignment: header ? .center : (right ? .trailing : .leading))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .border(Color.secondary.opacity(0.5), width: 0.5)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(header ? Color(.secondarySystemBackground) : Color.clear)
    }

    private var signs: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(model.signs.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.role).font(.subheadline.weight(.semibold))
                    Text((s.post.isEmpty ? "______________" : s.post) + "   ____________   " + (s.name.isEmpty ? "______________" : s.name)).font(.footnote)
                    Text("(должность)        (подпись)        (расшифровка подписи)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
