import SwiftUI
import UIKit

private let rqUnits = ["шт", "м", "м.п.", "м²", "м³", "кг", "т", "компл.", "пара", "уп.", "in"]
private let rqFormWidth: CGFloat = 720

// MARK: - Заявка: просмотр и правка

struct RequestEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let rec: Rec
    let isNew: Bool
    @State private var v: JSON = .o([:])
    @State private var items: [JSON] = []
    @State private var loaded = false
    @State private var lastCommit: JSON?
    @State private var showPrint = false

    var body: some View {
        Form {
            mainSection
            signSection
            supplySection
            ForEach(items.indices, id: \.self) { i in itemSection(i) }
            Section {
                Button { addItem() } label: { Label("Добавить позицию", systemImage: "plus.circle.fill") }
                Button { showPrint = true } label: { Label("Печать / PDF", systemImage: "printer") }.disabled(!hasContent)
            } footer: {
                if let validationError { Text(validationError).foregroundStyle(.red) }
                Text("«Получено» — сколько уже пришло на объект. Форму заявки можно распечатать или сохранить в PDF.")
            }
        }
        .frame(maxWidth: rqFormWidth)
        .frame(maxWidth: .infinity)
        .ptoScreen()
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .navigationTitle(isNew ? "Новая заявка" : "Заявка № " + Rq.title(v))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { toolbarContent }
        .onAppear { if !loaded { v = rec.v; items = rec["items"].arr; lastCommit = rec.v; loaded = true } }
        .onDisappear { if !isNew { commit() } }
        .onChange(of: phase) { p in if p != .active && !isNew { commit() } }
        .interactiveDismissDisabled(isNew && hasContent)
        .sheet(isPresented: $showPrint) { NavigationStack { RqPrintView(v: current) } }
    }

    // MARK: Разделы формы

    private var mainSection: some View {
        Section {
            labeled("Номер") { TextField("№", text: text("no")).keyboardType(.numbersAndPunctuation) }
            DatePicker("Дата", selection: date("date"), displayedComponents: .date)
            Picker("Раздел", selection: text("sec")) {
                Text("—").tag("")
                ForEach(store.reqSections) { Text($0.name).tag($0.id) }
                if !v["sec"].str.isEmpty && !store.reqSections.contains(where: { $0.id == v["sec"].str }) {
                    Text(v["sec"].str).tag(v["sec"].str)
                }
            }
            Picker("Цех / объект", selection: place("shop")) {
                if v["shop"].str.isEmpty { Text("—").tag("") }
                ForEach(store.shops, id: \.self) { Text($0).tag($0) }
                if !v["shop"].str.isEmpty && !store.shops.contains(v["shop"].str) { Text(v["shop"].str).tag(v["shop"].str) }
            }
            workField
            labeled("Шифр проекта") { TextField("330-2018-2-К", text: place("code")) }
            labeled("Договор") { TextField("Номер договора", text: contract) }
        } header: {
            Text("Заявка")
        } footer: {
            Text("В заявке: " + Rq.place(current))
        }
    }

    private var works: [String] {
        let fromCfg = store.cfg["works"].arr.map(\.str)
        let fromReqs = store.list("requests").map { $0["work"].str }
        var seen = Set<String>()
        return (fromCfg + fromReqs).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var workField: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Вид работ (после «для производства работ»)").font(.caption).foregroundStyle(.secondary)
                TextField("по сетям водоснабжения и канализации", text: place("work"), axis: .vertical)
            }
            if !works.isEmpty {
                Menu {
                    ForEach(works, id: \.self) { w in Button(w) { setPlaceField("work", w) } }
                } label: { Image(systemName: "list.bullet").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Выбрать вид работ")
            }
        }
    }

    private var signSection: some View {
        Section("Подписанты") {
            labeled("Выдал: должность") { TextField("Руководитель проекта", text: signField("ip")) }
            labeled("Выдал: ФИО") { TextField("ФИО", text: signField("in")) }
            labeled("Получил: должность") { TextField("Начальник участка", text: signField("rp")) }
            labeled("Получил: ФИО") { TextField("ФИО", text: signField("rn")) }
        }
    }

    private var supplySection: some View {
        Section {
            Picker("Поставка", selection: Binding(get: { Rq.status(v) }, set: { v["st"] = .s($0) })) {
                ForEach(reqStatuses, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Известна дата поставки", isOn: etaOn)
            if !v["eta"].str.isEmpty { DatePicker("Ожидаем к", selection: date("eta"), displayedComponents: .date) }
            labeled("М-15 / накладная") { TextField("номер или «есть»", text: text("m15")) }
            labeled("Пометка к заявке") { TextField("например: получено не всё", text: text("fnote")) }
        } header: {
            Text("Поставка")
        }
    }

    private func itemSection(_ i: Int) -> some View {
        Section {
            TextField("Наименование материала", text: itemText(i, "name"), axis: .vertical).font(.body.weight(.medium))
            HStack(spacing: 10) {
                numberBox("Кол-во", itemText(i, "qty"))
                unitBox(i)
                numberBox("Получено", itemText(i, "got"))
            }
            TextField("Назначение товара", text: itemText(i, "purpose"), axis: .vertical)
            TextField("ФИО заказчика", text: itemText(i, "cust"))
            TextField("Примечание", text: itemText(i, "note"), axis: .vertical)
        } header: {
            HStack {
                Text("Позиция \(i + 1)")
                Spacer()
                Button(role: .destructive) { removeItem(i) } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 32) }
                    .accessibilityLabel("Удалить позицию \(i + 1)")
            }
        }
    }

    private func numberBox(_ title: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("—", text: b).keyboardType(.decimalPad).monospacedDigit()
                .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func unitBox(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ед.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField("шт", text: itemText(i, "unit"))
                Menu {
                    ForEach(rqUnits, id: \.self) { u in Button(u) { setItem(i, "unit", u) } }
                } label: { Image(systemName: "chevron.up.chevron.down").font(.caption) }
                    .accessibilityLabel("Выбрать единицу")
            }
            .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isNew {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { commit(); dismiss() }.disabled(!hasContent || validationError != nil)
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ShareLink(item: Rq.itemsText(current)) { Label("Текстом", systemImage: "text.alignleft") }
                    ShareLink(item: RqCSVFile(name: sheetNow.fileBase + ".csv", text: sheetNow.csv()),
                              preview: SharePreview(sheetNow.fileBase + ".csv")) { Label("Для Excel (CSV)", systemImage: "tablecells") }
                    Button { showPrint = true } label: { Label("Печать / PDF", systemImage: "printer") }
                } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Поделиться")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }

    // MARK: Данные

    private var current: JSON {
        var out = v
        out["items"] = .a(items)
        return out
    }
    private var sheetNow: RqSheet { RqSheet.make(current, cfg: store.cfg, opt: RqPrintOpt(dropEmpty: false)) }

    private var hasContent: Bool { items.contains { !$0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty } }

    private var validationError: String? {
        if isNew {
            guard let number = v["no"].num, number.isFinite, number > 0,
                  number == number.rounded() else { return "Укажите целый положительный номер заявки." }
            if v["sec"].str.isEmpty { return "Выберите раздел." }
        }
        for item in items {
            for key in ["qty", "got"] {
                let raw = item[key].str.trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { continue }
                guard let number = item[key].num, number.isFinite, number >= 0 else {
                    return "Укажите корректное количество в каждой позиции."
                }
            }
        }
        return nil
    }

    private func addItem() {
        let unit = items.last?["unit"].str ?? "шт"
        withAnimation { items.append(Rq.newItem(store.cfg, unit: unit.isEmpty ? "шт" : unit)) }
    }
    private func removeItem(_ i: Int) {
        guard i < items.count else { return }
        withAnimation { _ = items.remove(at: i) }
    }

    private func commit() {
        guard loaded, validationError == nil, let previous = lastCommit else { return }
        if isNew && !hasContent { return }
        var out = v
        out["items"] = .a(items.map(normalizeItem))
        if let number = out["no"].num, number.isFinite { out["no"] = .n(number) }

        if isNew {
            store.put("requests", Rec(id: rec.id, v: out))
        } else if var latest = store.get("requests", rec.id) {
            let keys = Set(out.obj.keys).union(previous.obj.keys)
            let changed = keys.filter { out[$0] != previous[$0] }
            guard !changed.isEmpty else { return }
            for key in changed { latest.v[key] = out[key] }
            store.put("requests", latest)
        }
        lastCommit = out
    }

    private func normalizeItem(_ i: JSON) -> JSON {
        var x = i
        for k in ["qty", "got"] {
            let s = x[k].str.trimmingCharacters(in: .whitespaces)
            if let d = Double(s.replacingOccurrences(of: ",", with: ".")), d.isFinite {
                x[k] = .n(d)
            } else if s.isEmpty && k == "got" {
                x[k] = nil
            }
        }
        return x
    }

    // MARK: Привязки к полям записи

    private func text(_ k: String) -> Binding<String> {
        Binding(get: { v[k].str }, set: { new in
            v[k] = .s(new)
            if k == "no" { v["label"] = nil }
        })
    }
    /// Цех, вид работ и шифр собирают «назначение»: готовое назначение сбрасывается (как в вебе)
    private func place(_ k: String) -> Binding<String> {
        Binding(get: { v[k].str }, set: { setPlaceField(k, $0) })
    }
    private func setPlaceField(_ k: String, _ value: String) {
        v[k] = .s(value)
        v["place"] = nil
    }
    private var contract: Binding<String> {
        Binding(get: { Rq.contract(v, store.cfg) }, set: { v["contract"] = .s($0) })
    }
    private func signField(_ k: String) -> Binding<String> {
        Binding(get: { currentSign(k) }, set: { new in
            let s = Rq.sign(v, store.cfg)
            var d: [String: JSON] = ["ip": .s(s.ip), "in": .s(s.iname), "rp": .s(s.rp), "rn": .s(s.rname)]
            d[k] = .s(new)
            v["sign"] = .o(d)
        })
    }
    private func currentSign(_ k: String) -> String {
        let s = Rq.sign(v, store.cfg)
        switch k {
        case "ip": return s.ip
        case "in": return s.iname
        case "rp": return s.rp
        default: return s.rname
        }
    }
    private func date(_ k: String) -> Binding<Date> {
        Binding(get: { Fmt.date(v[k].str) ?? Date() }, set: { v[k] = .s(Fmt.iso.string(from: $0)) })
    }
    private var etaOn: Binding<Bool> {
        Binding(get: { !v["eta"].str.isEmpty }, set: { on in
            if on { v["eta"] = .s(Fmt.today) } else { v["eta"] = nil }
        })
    }
    private func itemText(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { i < items.count ? items[i][k].str : "" }, set: { setItem(i, k, $0) })
    }
    private func setItem(_ i: Int, _ k: String, _ value: String) {
        if i < items.count { items[i][k] = .s(value) }
    }
}
