import SwiftUI
import UIKit

// MARK: - Контакты

struct ContactsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var sheet: LsSheet?
    @State private var copied: String?

    private static let noOrg = "Без организации"
    private static let specs: [LsFieldSpec] = [
        LsFieldSpec(key: "name", title: "Имя"),
        LsFieldSpec(key: "role", title: "Должность"),
        LsFieldSpec(key: "org", title: "Организация"),
        LsFieldSpec(key: "phone", title: "Телефон", kind: .phone),
        LsFieldSpec(key: "email", title: "Электронная почта", kind: .email),
        LsFieldSpec(key: "note", title: "Заметка")
    ]

    private var all: [Rec] { store.list("contacts") }

    private var groups: [(org: String, items: [Rec])] {
        let q = query.lowercased()
        let found = all.filter { c in
            let hay = [c["name"].str, c["role"].str, c["org"].str, c["phone"].str, c["email"].str].joined(separator: " ").lowercased()
            return q.isEmpty || hay.contains(q)
        }
        let grouped = Dictionary(grouping: found) { (c: Rec) -> String in c["org"].str.isEmpty ? Self.noOrg : c["org"].str }
        let keys = grouped.keys.sorted { a, b in
            if (a == Self.noOrg) != (b == Self.noOrg) { return b == Self.noOrg }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return keys.map { k in
            (org: k, items: (grouped[k] ?? []).sorted { $0["name"].str.localizedCaseInsensitiveCompare($1["name"].str) == .orderedAscending })
        }
    }

    private var csv: LsCSV {
        let head = ["Имя", "Должность", "Организация", "Телефон", "Электронная почта", "Заметка"]
        let body: [[String]] = all.map { c in
            [c["name"].str, c["role"].str, c["org"].str, c["phone"].str, c["email"].str, c["note"].str]
        }
        return LsCSV(name: "Контакты.csv", rows: [head] + body)
    }

    var body: some View {
        List {
            if groups.isEmpty {
                EmptyNote(title: all.isEmpty ? "Контактов пока нет" : "Ничего не найдено",
                          text: all.isEmpty ? "Нажмите «+», чтобы добавить первый контакт." : "Измените поиск.")
            }
            ForEach(groups, id: \.org) { g in
                Section(g.org) {
                    ForEach(g.items) { c in row(c) }
                }
            }
        }
        .navigationTitle("Контакты")
        .searchable(text: $query, prompt: "Имя, должность, организация, телефон, почта")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !all.isEmpty { LsShareButton(csv: csv) }
                    Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Новый контакт")
                }
            }
        }
        .overlay(alignment: .bottom) { copiedToast }
        .sheet(item: $sheet) { s in form(s) }
        .lsColumn()
        .ptoScreen()
    }

    @ViewBuilder private var copiedToast: some View {
        if let copied {
            Text(copied).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16)
                .transition(.opacity)
        }
    }

    private func row(_ c: Rec) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { sheet = LsSheet(rec: c) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c["name"].str).font(.headline).foregroundStyle(.primary)
                    if !c["role"].str.isEmpty { Text(c["role"].str).font(.footnote).foregroundStyle(.secondary) }
                    if c["phone"].str.isEmpty && c["email"].str.isEmpty {
                        Text("телефон и почта не указаны").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: 2) {
                if !c["phone"].str.isEmpty {
                    action("phone.fill", "Позвонить", c["phone"].str) { call(c["phone"].str) }
                }
                if !c["email"].str.isEmpty {
                    action("envelope.fill", "Написать письмо", c["email"].str) { mail(c["email"].str) }
                }
            }
        }
        .contextMenu {
            if !c["phone"].str.isEmpty {
                Button { copy(c["phone"].str, "Номер скопирован") } label: { Label("Скопировать номер", systemImage: "doc.on.doc") }
            }
            if !c["email"].str.isEmpty {
                Button { copy(c["email"].str, "Адрес почты скопирован") } label: { Label("Скопировать почту", systemImage: "doc.on.doc") }
            }
        }
        .lsSwipeDelete { withAnimation { store.delete("contacts", c.id) } }
    }

    private func action(_ icon: String, _ label: String, _ value: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.footnote)
                Text(value).font(.footnote).lineLimit(1)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(label): \(value)")
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:" + digits) { openURL(url) }
    }

    private func mail(_ address: String) {
        if let url = URL(string: "mailto:" + address) { openURL(url) }
    }

    private func copy(_ text: String, _ message: String) {
        UIPasteboard.general.string = text
        LsHaptic.success()
        withAnimation { copied = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { copied = nil } }
    }

    private func validEmail(_ s: String) -> Bool {
        s.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
    }

    private func form(_ s: LsSheet) -> some View {
        let check: ([String: String]) -> String? = { d in
            let mail = (d["email"] ?? "").trimmingCharacters(in: .whitespaces)
            return mail.isEmpty || validEmail(mail) ? nil : "Проверьте адрес: он должен выглядеть как name@company.ru"
        }
        return LsRecordForm(title: s.rec == nil ? "Новый контакт" : "Контакт", specs: Self.specs, rec: s.rec,
                            required: (key: "name", message: "Укажите имя"), validate: check,
                            onSave: { r in withAnimation { store.put("contacts", r) } },
                            onDelete: { r in store.delete("contacts", r.id) })
    }
}
