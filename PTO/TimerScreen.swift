import SwiftUI
import UIKit
import AudioToolbox
import UserNotifications

// MARK: - Таймер: Помодоро. Время считается по сохранённой дате окончания, а не по фоновым потокам

private let lsFocusSeconds = 25 * 60
private let lsRestSeconds = 5 * 60
private let lsTimerNotificationId = "ls.timer"

struct TimerView: View {
    @AppStorage("ls.timer.rest") private var isRest = false
    @AppStorage("ls.timer.total") private var total = lsFocusSeconds
    @AppStorage("ls.timer.left") private var pausedLeft = Double(lsFocusSeconds)
    @AppStorage("ls.timer.end") private var endAt = 0.0
    @State private var now = Date()
    @State private var notice: String?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let presets: [(title: String, minutes: Int)] = [("Фокус 25", 25), ("Перерыв 5", 5), ("Длинный 15", 15)]

    private var running: Bool { endAt > 0 }
    private var remaining: Double { running ? max(0, endAt - now.timeIntervalSince1970) : pausedLeft }
    private var progress: Double { total > 0 ? min(1, max(0, 1 - remaining / Double(total))) : 0 }

    private var clock: String {
        let secs = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                presetBar
                ring
                controls
                Text("Метод Помодоро: 25 минут работы, 5 минут отдыха")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Таймер")
        .onReceive(ticker) { date in
            now = date
            if running && remaining <= 0 { finish() }
        }
        .onChange(of: phase) { _ in
            now = Date()
            if running && remaining <= 0 { finish() }
        }
        .ptoScreen()
    }

    private var presetBar: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.minutes) { p in
                Chip(title: p.title, on: total == p.minutes * 60) { choose(p.minutes) }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 14)
            Circle().trim(from: 0, to: progress)
                .stroke(isRest ? Color.green : Color.pto, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.5), value: progress)
            VStack(spacing: 4) {
                Text(clock).font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(isRest ? "Перерыв" : "Фокус").foregroundStyle(.secondary)
                if let notice { Text(notice).font(.footnote.weight(.medium)).foregroundStyle(Color.pto) }
            }
            .padding(24)
        }
        .frame(maxWidth: 300, maxHeight: 300)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRest ? "Перерыв" : "Фокус")
        .accessibilityValue(clock)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { running ? pause() : start() } label: {
                Text(running ? "Пауза" : "Старт").frame(minWidth: 110, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            Button { reset() } label: { Text("Сбросить").frame(minHeight: 36) }
                .buttonStyle(.bordered)
        }
    }

    // MARK: Действия

    private func start() {
        if pausedLeft <= 0 { pausedLeft = Double(total) }
        endAt = Date().timeIntervalSince1970 + pausedLeft
        now = Date()
        notice = nil
        schedule(after: pausedLeft, body: isRest ? "Пора за работу!" : "Время отдохнуть!")
        LsHaptic.tap()
    }

    private func pause() {
        pausedLeft = remaining
        endAt = 0
        cancelNotification()
        LsHaptic.tap()
    }

    private func reset() {
        endAt = 0
        pausedLeft = Double(total)
        notice = nil
        cancelNotification()
        LsHaptic.tap()
    }

    private func choose(_ minutes: Int) {
        endAt = 0
        total = minutes * 60
        pausedLeft = Double(total)
        isRest = minutes != 25
        notice = nil
        cancelNotification()
    }

    private func finish() {
        let overdue = Date().timeIntervalSince1970 - endAt
        endAt = 0
        cancelNotification()
        if overdue < 5 { alert() }
        notice = isRest ? "Пора за работу!" : "Время отдохнуть!"
        isRest.toggle()
        total = isRest ? lsRestSeconds : lsFocusSeconds
        pausedLeft = Double(total)
    }

    private func alert() {
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        LsHaptic.success()
    }

    // MARK: Уведомление на случай, когда приложение свёрнуто

    private func schedule(after seconds: Double, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Таймер"
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: lsTimerNotificationId, content: content, trigger: trigger))
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [lsTimerNotificationId])
    }
}
