import SwiftUI

// MARK: - Моя работа (справочная страница, как в вебе)

private struct LsFact: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

private struct LsPerson: Identifiable {
    let role: String
    let org: String
    let people: String
    var id: String { role }
}

struct WorkView: View {
    @EnvironmentObject var store: Store

    private var company: String {
        let c = store.cfg["company"].str
        return c.isEmpty ? "ООО «СК «Артэк»" : c
    }

    private var position: [LsFact] {
        [LsFact(title: "Роль", value: "Инженер ПТО (производственно-технический отдел)"),
         LsFact(title: "Организация", value: company + " — монтажная организация (субподрядчик)"),
         LsFact(title: "Зона ответственности", value: "Исполнительная документация, объёмы и закрытия КС, ТМЦ и давальческие материалы, входной контроль и документы качества, графики, чертежи и изменения проекта, подготовка к приёмке")]
    }

    private let site: [LsFact] = [
        LsFact(title: "Наименование", value: "Строительство молочного завода с производительностью 1150 т молока в сутки"),
        LsFact(title: "Место", value: "р.п. Маслянино, Маслянинский район, Новосибирская область; земельный участок с кадастровым номером 54:17:024208:1304 (Пеньковский сельсовет)"),
        LsFact(title: "Шифр проекта", value: "330-2018-2 (например, ВК1.1, К)"),
        LsFact(title: "Цеха", value: "Цех производства сыра № 2 по ГП; Аппаратный цех"),
        LsFact(title: "Системы", value: "В1.1, В1, Т3, Т4, В1вд, Т3вд; изоляция трубопроводов (К-Флекс); опорные конструкции")
    ]

    private let team: [LsPerson] = [
        LsPerson(role: "Застройщик / технический заказчик", org: "ООО «ЭкоНиваАгро»", people: "Ерыпалов С.Г., заместитель главного инженера"),
        LsPerson(role: "Генеральный подрядчик", org: "ООО «НиваСтрой»", people: "Грибков А.В., руководитель проекта по строительству; Любимов П.Н., прораб"),
        LsPerson(role: "Проектировщик", org: "ООО «НиваПроект»", people: "—"),
        LsPerson(role: "Монтажная организация (вы)", org: "ООО «СК АРТЭК»", people: "Талаш Н.Б., начальник участка; Красов А.С., начальник участка (заявки); Юстус А.В., генеральный директор"),
        LsPerson(role: "Эксплуатационная организация", org: "ООО «САМН»", people: "Пешко Н.Н., начальник участка очистных сооружений и водоподготовки; Быковский А.В., главный инженер")
    ]

    private let contracts = [
        "№ 28/11/2025-SZ от 28.11.2025 — основной (ОДМ, заявки на ТМЦ)",
        "№ П-СК-2004/26 от 20.04.2026 — «Партнёр» (акты выполненных работ)",
        "№ П-СК-2005/26 от 22.05.2026 — ИП Богданова (изоляция К-Флекс)"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Кто вы, где работаете и кто есть кто на объекте")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Card(title: "Должность") { facts(position) }
                Card(title: "Объект") { facts(site) }
                Card(title: "Кто есть кто") {
                    ForEach(team) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.role).font(.subheadline.weight(.semibold))
                            Text(p.org).font(.subheadline).foregroundStyle(Color.pto)
                            Text(p.people).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                Card(title: "Договоры (по вашим документам)") {
                    ForEach(contracts, id: \.self) { Text($0).font(.subheadline) }
                    Text("Данные собраны из ваших файлов. Проверьте и поправьте в «Настройках».")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                links
            }
            .padding(16)
            .lsColumn()
        }
        .navigationTitle("Моя работа")
        .ptoScreen()
    }

    private func facts(_ items: [LsFact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title).font(.caption).foregroundStyle(.secondary)
                    Text(f.value).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var links: some View {
        VStack(spacing: 10) {
            link("Нормативка", "book") { NormsView() }
            link("Шпаргалки ПТО", "exclamationmark.triangle") { CheatView() }
            link("Сортамент труб", "cylinder.split.1x2") { PipesView() }
        }
    }

    private func link<D: View>(_ title: String, _ icon: String, @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(Color.pto).frame(width: 28)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(14).frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Pressable())
    }
}
