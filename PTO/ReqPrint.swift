import SwiftUI
import PDFKit
import UIKit
import UniformTypeIdentifiers

// MARK: - Данные печатной формы (всё строками, чтобы передавать в фоновое создание файла)

struct RqSheetRow: Sendable {
    let n: String, name: String, unit: String, qty: String, purpose: String, cust: String, note: String
}

struct RqSheet: Sendable {
    let title: String
    let intro: String
    let place: String
    let dateText: String
    let contract: String
    let rows: [RqSheetRow]
    let issuerPost: String, issuerName: String
    let receiverPost: String, receiverName: String
    let fileBase: String

    static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    /// «05» марта 2026 год
    static func longDate(_ s: String) -> String {
        guard let d = Fmt.date(s) else { return "«__» ________ 20__ год" }
        let c = Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: d)
        let day = String(format: "%02d", c.day ?? 1)
        return "«\(day)» \(months[max(0, min(11, (c.month ?? 1) - 1))]) \(c.year ?? 0) год"
    }

    private static func pick(_ list: [Rq.Signer], _ i: Int?) -> Rq.Signer? {
        guard let i, i >= 0, i < list.count else { return nil }
        return list[i]
    }

    static func make(_ v: JSON, cfg: JSON, opt: RqPrintOpt) -> RqSheet {
        var items = v["items"].arr
        if opt.dropEmpty { items = items.filter { !$0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty } }
        var data = v
        if let shop = opt.shop { data["shop"] = .s(shop) }
        let issuers = Rq.issuers(cfg), receivers = Rq.receivers(cfg)
        let iss: Rq.Signer? = Self.pick(issuers, opt.issuer)
        let rec: Rq.Signer? = Self.pick(receivers, opt.receiver)
        let s = Rq.sign(data, cfg, issuer: iss, receiver: rec)
        let rows = items.enumerated().map { (k: Int, i: JSON) -> RqSheetRow in
            RqSheetRow(n: String(k + 1), name: i["name"].str, unit: i["unit"].str, qty: i["qty"].str,
                       purpose: i["purpose"].str, cust: i["cust"].str, note: i["note"].str)
        }
        return RqSheet(title: "ЗАЯВКА №" + Rq.title(v), intro: "на поставку стройматериалов " + cfg["company"].str,
                       place: Rq.place(data), dateText: longDate(v["date"].str), contract: Rq.contract(v, cfg),
                       rows: rows, issuerPost: s.ip, issuerName: s.iname, receiverPost: s.rp, receiverName: s.rname,
                       fileBase: "Заявка_№" + v["no"].str)
    }

    func csv() -> String {
        var l: [[String]] = [[title], [intro], [place], [dateText, "", "", "", contract], [],
                             ["№ п/п", "Наименование материала", "Ед. изм.", "Кол.-во", "Назначение товара", "ФИО заказчика", "Примечание"]]
        for r in rows { l.append([r.n, r.name, r.unit, r.qty, r.purpose, r.cust, r.note]) }
        l.append([])
        l.append(["Выдал:"]); l.append(["\(issuerPost) ____________________ \(issuerName)"]); l.append([])
        l.append(["Получил:"]); l.append(["\(receiverPost) ____________________ \(receiverName)"])
        return Rq.csv(l)
    }
}

/// Что уточняет веб перед печатью (askPrint)
struct RqPrintOpt: Equatable {
    var issuer: Int?
    var receiver: Int?
    var dropEmpty = true
    var shop: String?
}

// MARK: - Рисование PDF формата A4

enum RqPDF {
    private static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let margin: CGFloat = 40
    private static let widths: [CGFloat] = [30, 160, 40, 42, 98, 70, 75]
    private static let heads = ["№ п/п", "Наименование материала", "Ед. изм.", "Кол.-во", "Назначение товара", "ФИО заказчика", "Примечание"]

    private static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT", size: size)
            ?? (bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size))
    }
    private static func attrs(_ f: UIFont, _ a: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = a
        p.lineBreakMode = .byWordWrapping
        return [.font: f, .paragraphStyle: p, .foregroundColor: UIColor.black]
    }
    private static func height(_ s: String, _ w: CGFloat, _ f: UIFont) -> CGFloat {
        let r = (s as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: attrs(f, .left), context: nil)
        return ceil(r.height)
    }
    @discardableResult
    private static func draw(_ s: String, _ rect: CGRect, _ f: UIFont, _ a: NSTextAlignment) -> CGFloat {
        (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs(f, a), context: nil)
        return rect.height
    }

    static func render(_ sh: RqSheet) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            let width = page.width - margin * 2
            let limit = page.height - margin
            var y = margin
            ctx.beginPage()

            func line(_ s: String, _ f: UIFont, _ a: NSTextAlignment, gap: CGFloat = 4) {
                let h = height(s, width, f)
                if y + h > limit { ctx.beginPage(); y = margin }
                draw(s, CGRect(x: margin, y: y, width: width, height: h), f, a)
                y += h + gap
            }

            line(sh.title, font(15, bold: true), .center, gap: 6)
            line(sh.intro, font(11), .center)
            line(sh.place, font(11), .center, gap: 8)
            let dh = max(height(sh.dateText, width / 2, font(11)), height(sh.contract, width / 2, font(11)))
            draw(sh.dateText, CGRect(x: margin, y: y, width: width / 2, height: dh), font(11), .left)
            draw(sh.contract, CGRect(x: margin + width / 2, y: y, width: width / 2, height: dh), font(11), .right)
            y += dh + 10

            func row(_ cells: [String], bold: Bool, align: [NSTextAlignment]) {
                let f = font(10, bold: bold)
                let inner = zip(cells, widths).map { height($0, $1 - 6, f) }
                let h = (inner.max() ?? 12) + 8
                if y + h > limit { ctx.beginPage(); y = margin }
                var x = margin
                for (k, c) in cells.enumerated() {
                    let cell = CGRect(x: x, y: y, width: widths[k], height: h)
                    UIColor.black.setStroke()
                    ctx.cgContext.setLineWidth(0.6)
                    ctx.cgContext.stroke(cell)
                    draw(c, cell.insetBy(dx: 3, dy: 4), f, align[k])
                    x += widths[k]
                }
                y += h
            }

            let center: [NSTextAlignment] = [.center, .center, .center, .center, .center, .center, .center]
            let body: [NSTextAlignment] = [.center, .left, .center, .center, .left, .left, .left]
            row(heads, bold: true, align: center)
            for r in sh.rows { row([r.n, r.name, r.unit, r.qty, r.purpose, r.cust, r.note], bold: false, align: body) }

            y += 24
            if y + 130 > limit { ctx.beginPage(); y = margin }
            line("Выдал:", font(11, bold: true), .left, gap: 6)
            line("\(sh.issuerPost) ____________________ \(sh.issuerName)", font(11), .left, gap: 22)
            line("Получил:", font(11, bold: true), .left, gap: 6)
            line("\(sh.receiverPost) ____________________ \(sh.receiverName)", font(11), .left)
        }
    }
}

struct RqPDFFile: Transferable {
    let sheet: RqSheet
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { (f: RqPDFFile) -> SentTransferredFile in
            let url = try RqTemp.write(f.sheet.fileBase + ".pdf", RqPDF.render(f.sheet))
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Просмотр, печать и отправка

private struct RqPDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .secondarySystemBackground
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) { v.document = PDFDocument(data: data) }
}

struct RqPrintView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let v: JSON
    @State private var opt = RqPrintOpt()
    @State private var pdf = Data()

    private var issuers: [Rq.Signer] { Rq.issuers(store.cfg) }
    private var receivers: [Rq.Signer] { Rq.receivers(store.cfg) }
    private var hasEmpty: Bool { v["items"].arr.contains { $0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var hasChoices: Bool {
        (v["sign"] == nil && (issuers.count > 1 || receivers.count > 1)) || hasEmpty || v["shop"].str.isEmpty
    }
    private var sheet: RqSheet { RqSheet.make(v, cfg: store.cfg, opt: opt) }
    private func label(_ s: Rq.Signer) -> String { (s.post.isEmpty ? "" : s.post + " — ") + s.name }

    var body: some View {
        Group {
            if pdf.isEmpty { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } else { RqPDFPreview(data: pdf) }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Печать / PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            ToolbarItemGroup(placement: .confirmationAction) {
                if hasChoices { optionsMenu }
                Button { printIt() } label: { Image(systemName: "printer") }.accessibilityLabel("Печать").disabled(pdf.isEmpty)
                ShareLink(item: RqPDFFile(sheet: sheet), preview: SharePreview(sheet.fileBase + ".pdf")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Отправить PDF")
            }
        }
        .onAppear { refresh() }
        .onChange(of: opt) { _ in refresh() }
    }

    private var optionsMenu: some View {
        Menu {
            if v["sign"] == nil && issuers.count > 1 {
                Picker("Кто выдаёт", selection: Binding(get: { opt.issuer ?? 0 }, set: { opt.issuer = $0 })) {
                    ForEach(issuers.indices, id: \.self) { Text(label(issuers[$0])).tag($0) }
                }
            }
            if v["sign"] == nil && receivers.count > 1 {
                Picker("Кто получает", selection: Binding(get: { opt.receiver ?? 0 }, set: { opt.receiver = $0 })) {
                    ForEach(receivers.indices, id: \.self) { Text(label(receivers[$0])).tag($0) }
                }
            }
            if hasEmpty { Toggle("Не печатать пустые строки", isOn: $opt.dropEmpty) }
            if v["shop"].str.isEmpty {
                Picker("Цех", selection: Binding(get: { opt.shop ?? "" }, set: { opt.shop = $0 })) {
                    Text("Без цеха").tag("")
                    ForEach(store.shops, id: \.self) { Text($0).tag($0) }
                }
            }
        } label: { Image(systemName: "slider.horizontal.3") }
            .accessibilityLabel("Параметры печати")
    }

    private func refresh() { pdf = RqPDF.render(sheet) }

    private func printIt() {
        let c = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = sheet.fileBase
        c.printInfo = info
        c.printingItem = pdf
        c.present(animated: true, completionHandler: nil)
    }
}
