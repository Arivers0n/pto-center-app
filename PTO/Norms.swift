import SwiftUI

// MARK: - Данные нормативки (как NORM в вебе)

private struct ClNorm {
    let group: String
    let code: String
    let title: String
    let use: String
    let verified: Bool
}

private let clNormChecked = "14.11.2026"
private let clAllGroups = "Все"

private let clNorms: [ClNorm] = [
    ClNorm(group: "ИД и порядок", code: "Приказ Минстроя России от 16.05.2023 № 344/пр", title: "Состав и порядок ведения исполнительной документации", use: "Формы: общий журнал работ, АОСР (прил. 3), акты, реестр ИД. Действует с 01.09.2023 до 01.09.2029", verified: true),
    ClNorm(group: "ИД и порядок", code: "ГОСТ Р 70108-2025", title: "Документация исполнительная. Формирование и ведение в электронном виде", use: "С 01.10.2025. Приоритет XML-формата; перечень ИД утверждает заказчик до начала строительства и включает в договор; уведомление об освидетельствовании — не позднее чем за 3 рабочих дня", verified: true),
    ClNorm(group: "ИД и порядок", code: "Постановление Госкомстата России от 11.11.1999 № 100", title: "Унифицированные формы КС-2 (акт о приёмке выполненных работ) и КС-3 (справка о стоимости)", use: "Закрытия: листы «КС-2» и «КС-3» в книге повторяют эти формы", verified: true),
    ClNorm(group: "ИД и порядок", code: "Градостроительный кодекс РФ, ст. 53", title: "Строительный контроль", use: "Права и обязанности при освидетельствовании работ и ИД", verified: false),
    ClNorm(group: "ИД и порядок", code: "Постановление Правительства РФ от 21.06.2010 № 468", title: "Порядок проведения строительного контроля", use: "Кто и как осуществляет контроль, уведомления, замечания", verified: false),
    ClNorm(group: "ИД и порядок", code: "СП 48.13330.2019", title: "Организация строительства", use: "ПОС/ППР, входной контроль, приёмка работ", verified: false),
    ClNorm(group: "Приёмка и испытания", code: "СП 68.13330.2017 (Изм. 1 — приказ № 795/пр от 10.12.2019)", title: "Приёмка в эксплуатацию законченных строительством объектов. Основные положения", use: "П. 6.6: приёмка оборудования после индивидуальных испытаний (ваш «Акт приёмки после индивидуального испытания»), затем комплексное опробование", verified: true),
    ClNorm(group: "Приёмка и испытания", code: "СП 73.13330.2016 (с изменениями, есть Изм. № 3)", title: "Внутренние санитарно-технические системы", use: "Разд. 7 — испытания: гидростатический или манометрический метод, акт по прил. В; канализация — прил. Г; промывка — п. 6.1.13. Отопление/холодоснабжение: пробное давление 1,5 Рраб, не менее 0,2 МПа в нижней точке", verified: true),
    ClNorm(group: "Приёмка и испытания", code: "СП 129.13330.2019", title: "Наружные сети и сооружения водоснабжения и канализации", use: "Если на объекте есть наружные сети", verified: false),
    ClNorm(group: "Приёмка и испытания", code: "СП 61.13330.2012", title: "Тепловая изоляция оборудования и трубопроводов", use: "Изоляция К-Флекс и др.: требования к монтажу и приёмке", verified: false),
    ClNorm(group: "Приёмка и испытания", code: "СП 70.13330.2012", title: "Несущие и ограждающие конструкции", use: "Опоры, балки, металлоконструкции под трубопроводы, АОСР на опорные конструкции", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 8732-78", title: "Трубы стальные бесшовные горячедеформированные. Сортамент", use: "Чёрные трубы большого диаметра (⌀57…⌀325 из ваших КС)", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 8734-75", title: "Трубы стальные бесшовные холоднодеформированные. Сортамент", use: "Малые диаметры", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 10704-91", title: "Трубы стальные электросварные прямошовные. Сортамент", use: "Электросварные трубы", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 3262-75", title: "Трубы стальные водогазопроводные", use: "Водогазопроводные (дюймовые) трубы", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 9941-81", title: "Трубы бесшовные холодно- и теплодеформированные из коррозионно-стойкой стали", use: "Нержавейка бесшовная (AISI 304 и др.)", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 11068-81", title: "Трубы электросварные из коррозионно-стойкой стали", use: "Нержавейка сварная", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 5632-2014", title: "Нержавеющие стали и сплавы. Марки", use: "Соответствие AISI ↔ ГОСТ-марки (см. шпаргалки)", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 17375-2001 / 17376-2001 / 17378-2001", title: "Детали трубопроводов: отводы / тройники / переходы", use: "Фасонина по заявкам на ТМЦ", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 33259-2015", title: "Фланцы арматуры, соединительных частей и трубопроводов (PN до 250)", use: "Фланцевые соединения, затворы, краны", verified: false),
    ClNorm(group: "Трубы и детали", code: "ГОСТ 32415-2013", title: "Трубы напорные из термопластов и соединительные детали для систем водоснабжения и отопления", use: "Полипропилен PPR (⌀20…⌀50 из вашего свода КС)", verified: false),
    ClNorm(group: "Сварка и контроль", code: "ГОСТ 16037-80", title: "Соединения сварные стальных трубопроводов. Основные типы", use: "Конструктивные элементы сварных стыков", verified: false),
    ClNorm(group: "Сварка и контроль", code: "ГОСТ 14771-76 / ГОСТ 5264-80", title: "Сварка в защитном газе / ручная дуговая сварка. Основные типы соединений", use: "Подготовка кромок и швы", verified: false),
    ClNorm(group: "Сварка и контроль", code: "ГОСТ Р ИСО 5817-2009", title: "Сварные соединения (кроме лучевой сварки). Уровни качества", use: "Оценка дефектов стыков", verified: false),
    ClNorm(group: "Сварка и контроль", code: "ГОСТ 7512-82 / ГОСТ Р 55724-2013 / ГОСТ 23479-79", title: "Радиографический / ультразвуковой / оптический (визуальный) контроль", use: "Методы контроля стыков — основа для реестра стыков", verified: false),
    ClNorm(group: "Сварка и контроль", code: "ГОСТ 32569-2013", title: "Трубопроводы технологические стальные. Требования к устройству и эксплуатации (взрывопожароопасные производства)", use: "Применять, только если на него есть ссылка в проекте (раздел ТХ/ТК)", verified: false),
    ClNorm(group: "Проект", code: "ГОСТ Р 21.101-2020", title: "СПДС. Основные требования к проектной и рабочей документации", use: "Основа для чтения чертежей, марки комплектов (ТИ — тепловая изоляция и др.)", verified: true),
    ClNorm(group: "Проект", code: "ГОСТ 21.601-2011 / ГОСТ 21.602-2016", title: "СПДС. Водоснабжение и канализация / отопление, вентиляция и кондиционирование", use: "Рабочие чертежи систем В1, Т3, Т4", verified: false),
    ClNorm(group: "Проект", code: "ГОСТ 21.206-2012 / ГОСТ 21.205-2016", title: "СПДС. Условные обозначения трубопроводов / элементов санитарно-технических систем", use: "Читать и рисовать исполнительные схемы", verified: false),
    ClNorm(group: "Пищевое производство", code: "ТР ТС 021/2011", title: "О безопасности пищевой продукции", use: "Требования к производству и оборудованию, контактирующему с продукцией", verified: false),
    ClNorm(group: "Пищевое производство", code: "ТР ТС 033/2013", title: "О безопасности молока и молочной продукции", use: "Профильный регламент для молочного завода", verified: false),
    ClNorm(group: "Охрана труда", code: "Приказ Минтруда России от 11.12.2020 № 883н", title: "Правила по охране труда при строительстве, реконструкции и ремонте", use: "Наряды-допуски, инструктажи, строительные работы", verified: false),
    ClNorm(group: "Охрана труда", code: "Приказ Минтруда России от 16.11.2020 № 782н", title: "Правила по охране труда при работе на высоте", use: "Монтаж на техэтаже, отм. +11.400 и выше", verified: false)
]

private let clNormGroups: [String] = {
    var seen: [String] = [clAllGroups]
    for n in clNorms where !seen.contains(n.group) { seen.append(n.group) }
    return seen
}()

// MARK: - Экран «Нормативка»

struct NormsView: View {
    @State private var group = clAllGroups
    @State private var query = ""
    @State private var toast: String?

    private var rows: [ClNorm] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return clNorms.filter { n in
            guard group == clAllGroups || n.group == group else { return false }
            if q.isEmpty { return true }
            let hay = [n.group, n.code, n.title, n.use].joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                legend
                groupChips
                if rows.isEmpty {
                    EmptyNote(title: "Ничего не найдено", text: "Измените запрос или выберите другой раздел")
                }
                ForEach(rows, id: \.code) { row($0) }
                Text("Нажмите на документ, чтобы скопировать его обозначение.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .clColumn()
        }
        .ptoScreen()
        .navigationTitle("Нормативка")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Номер, слово, «сварка», «КС»…")
        .clToast($toast)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Как читать").font(.headline)
                Spacer()
                Badge(text: "Сверено: \(clNormChecked)", color: .green)
            }
            Text("«Сверено» — статус и содержание проверены по открытым источникам на \(clNormChecked). «Справочно» — документ из практики, статус перед применением сверьте в вашей системе (Консультант / Техэксперт). Здесь краткая памятка, а не текст документов. Размеры и давления берите из проекта и самих документов.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(clNormGroups, id: \.self) { g in
                    Chip(title: g, on: g == group) { group = g }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func searchURL(_ n: ClNorm) -> URL? {
        let q = n.code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://yandex.ru/search/?text=" + q)
    }

    private func row(_ n: ClNorm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                clCopy(n.code)
                toast = "Скопировано: \(n.code)"
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.code).font(.headline).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Badge(text: n.verified ? "Сверено" : "Справочно", color: n.verified ? .green : .secondary)
                    }
                    Text(n.title).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    Text(n.use).font(.subheadline).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Скопировать обозначение документа")
            if let url = searchURL(n) {
                Link(destination: url) {
                    Label("Найти текст документа", systemImage: "safari").font(.subheadline)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
