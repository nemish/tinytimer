import AppKit
import SwiftUI

// MARK: - Pure logic

func format(_ seconds: Int) -> String {
    let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

/// True when the elapsed time crossed a multiple of `every` seconds between two ticks.
/// With `repeats` off, only the first crossing fires.
func chimeDue(prev: TimeInterval, now: TimeInterval, every: Int, repeats: Bool = true) -> Bool {
    every > 0 && Int(now) / every > Int(prev) / every && (repeats || Int(prev) < every)
}

if CommandLine.arguments.contains("--selftest") {
    precondition(format(0) == "00:00" && format(65) == "01:05" && format(3725) == "1:02:05")
    precondition(chimeDue(prev: 29.9, now: 30.1, every: 30))
    precondition(!chimeDue(prev: 30.1, now: 30.3, every: 30))
    precondition(!chimeDue(prev: 0, now: 0.2, every: 30))
    precondition(!chimeDue(prev: 29.9, now: 30.1, every: 0))
    precondition(chimeDue(prev: 29.9, now: 30.1, every: 30, repeats: false))
    precondition(!chimeDue(prev: 59.9, now: 60.1, every: 30, repeats: false))
    print("selftest ok")
    exit(0)
}

// MARK: - Model

/// A run of finished countdowns (one Pomodoro sitting). The last element of `sessions` is the current one.
struct Session: Codable, Identifiable {
    var id = UUID()
    var start = Date()
    var minutes: [Int] = []  // length of each finished countdown; one dot each
}

final class TimerModel: ObservableObject {
    enum Mode: String { case stopwatch, countdown }

    private let d = UserDefaults.standard
    @Published var mode: Mode { didSet { d.set(mode.rawValue, forKey: "mode"); reset() } }
    @Published var countdownMin: Int { didSet { d.set(countdownMin, forKey: "countdownMin") } }
    @Published var chimeEvery: Int { didSet { d.set(chimeEvery, forKey: "chimeEvery") } }  // seconds, 0 = off
    @Published var pinned: Bool { didSet { d.set(pinned, forKey: "pinned") } }
    @Published var sound: String { didSet { d.set(sound, forKey: "sound"); loadChime() } }
    @Published var chimeRepeat: Bool { didSet { d.set(chimeRepeat, forKey: "chimeRepeat") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume"); chime?.volume = Float(volume) } }
    @Published var doneSound: String { didSet { d.set(doneSound, forKey: "doneSound"); loadDone() } }
    @Published var doneVolume: Double { didSet { d.set(doneVolume, forKey: "doneVolume"); done?.volume = Float(doneVolume) } }
    @Published var sessions: [Session] { didSet { d.set(try? JSONEncoder().encode(sessions), forKey: "sessions") } }
    var completed: Int { sessions.last?.minutes.count ?? 0 }  // finished countdowns in the current session
    @Published var doneRepeat: Bool { didSet { d.set(doneRepeat, forKey: "doneRepeat") } }
    static let sounds = ["bell", "chime", "bowl", "kalimba", "marimba", "wood", "drop", "tink"]  // single hits
    static let rings = ["phone", "digital", "melody", "bells", "pulse", "harp"]  // ringtone-style patterns

    @Published var expanded = false {
        didSet { if expanded { stopRinging() } else { showPrefs = false; showSessions = false } }
    }
    @Published var showSessions = false
    @Published var showPrefs = false
    @Published var hovering = false
    @Published var elapsed: TimeInterval = 0
    @Published var running = false
    @Published var notchW: CGFloat = 180
    @Published var notchH: CGFloat = 0

    private var base: TimeInterval = 0
    private var startedAt: Date?
    private var ticker: Timer?
    private var chime: NSSound?
    private var done: NSSound?

    init() {
        d.register(defaults: ["mode": "stopwatch", "countdownMin": 25, "chimeEvery": 60, "pinned": true, "sound": "bell",
                                  "chimeRepeat": true, "volume": 0.3, "doneSound": "glass", "doneVolume": 0.5])
        mode = Mode(rawValue: d.string(forKey: "mode") ?? "") ?? .stopwatch
        countdownMin = d.integer(forKey: "countdownMin")
        chimeEvery = d.integer(forKey: "chimeEvery")
        pinned = d.bool(forKey: "pinned")
        sound = d.string(forKey: "sound") ?? "bell"
        chimeRepeat = d.bool(forKey: "chimeRepeat")
        volume = d.double(forKey: "volume")
        doneSound = d.string(forKey: "doneSound") ?? "glass"
        doneVolume = d.double(forKey: "doneVolume")
        sessions = d.data(forKey: "sessions").flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []
        doneRepeat = d.bool(forKey: "doneRepeat")
        if sessions.isEmpty {  // first run; carry over the old plain counter if there was one
            sessions = [Session(minutes: Array(repeating: countdownMin, count: d.integer(forKey: "completed")))]
        }
        startFreshIfStale()
        loadChime()
        loadDone()
    }

    var duration: TimeInterval { TimeInterval(countdownMin * 60) }
    var display: String {
        mode == .stopwatch ? format(Int(elapsed)) : format(Int(max(0, duration - elapsed).rounded(.up)))
    }
    var shown: Bool { pinned || hovering || expanded }
    /// Size of the black shape hanging from the top edge (includes the notch itself).
    var size: CGSize {
        if showPrefs || showSessions { return CGSize(width: max(notchW, 340), height: notchH + 256) }
        if expanded { return CGSize(width: max(notchW, 340), height: notchH + (mode == .countdown ? 162 : 128)) }
        return CGSize(width: notchW, height: shown ? notchH + 26 : max(notchH, 5))
    }

    func toggle() {
        stopRinging()
        if running {
            base = elapsed; startedAt = nil; ticker?.invalidate(); running = false
        } else {
            if mode == .countdown && elapsed >= duration { base = 0; elapsed = 0 }
            startedAt = Date(); running = true
            let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        }
    }

    /// Yesterday's session doesn't continue today.
    private func startFreshIfStale() {
        if completed > 0, !Calendar.current.isDateInToday(sessions[sessions.count - 1].start) { sessions.append(Session()) }
    }

    func newSession() {
        if completed > 0 { sessions.append(Session()) }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if sessions.last?.minutes.isEmpty != true { sessions.append(Session()) }  // keep an open current session
    }

    private func recordFinish() {
        startFreshIfStale()
        var all = sessions
        if all[all.count - 1].minutes.isEmpty { all[all.count - 1].start = Date() }
        all[all.count - 1].minutes.append(countdownMin)
        // ponytail: history lives in UserDefaults, capped at 200 sessions; move to a file if it needs to grow.
        sessions = Array(all.suffix(200))
    }

    func restart() {
        reset()
        toggle()
    }

    func reset() {
        stopRinging()
        if running { toggle() }
        base = 0; elapsed = 0
    }

    /// Bundled mp3 from sounds/, else a system sound of that name ("tink" -> Tink, "glass" -> Glass).
    private func load(_ name: String, volume: Double) -> NSSound? {
        let snd = Bundle.main.url(forResource: name, withExtension: "mp3")
            .flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: name.capitalized)
        snd?.volume = Float(volume)
        return snd
    }
    private func loadChime() { chime?.stop(); chime = load(sound, volume: volume) }
    private func loadDone() { done?.stop(); done = load(doneSound, volume: doneVolume) }

    func playDone() { chime?.stop(); done?.stop(); done?.loops = false; done?.play() }

    /// Countdown finished: play the finish sound, looping until dismissed if "Repeating" is on.
    private var ringing = false
    private func ring() {
        playDone()
        guard doneRepeat else { return }
        done?.loops = true
        ringing = true
        // ponytail: hard 60s cap so it can't ring forever in an empty room; make it a setting if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.stopRinging() }
    }
    func stopRinging() {
        guard ringing else { return }
        ringing = false
        done?.stop()
    }
    func playChime() { chime?.stop(); chime?.play() }

    private func tick() {
        guard let startedAt else { return }
        let prev = elapsed
        let now = base + Date().timeIntervalSince(startedAt)
        if mode == .countdown && now >= duration {
            toggle()
            base = 0; elapsed = 0  // back to the full duration, ready to start again
            recordFinish()
            ring()
            return
        }
        elapsed = now
        if chimeDue(prev: prev, now: now, every: chimeEvery, repeats: chimeRepeat) { playChime() }
    }
}

// MARK: - View

struct NotchView: View {
    @ObservedObject var m: TimerModel
    @State private var finishTab = false  // Preferences: editing the countdown-finished sound

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: m.notchH)
            if m.showPrefs { prefs } else if m.showSessions { sessionsView } else if m.expanded { panel } else if m.shown { compact }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .top)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: m.expanded ? 18 : 10,
                                          bottomTrailingRadius: m.expanded ? 18 : 10))
        .contentShape(Rectangle())
        // Drag down: hidden -> pinned -> expanded. Drag up: the reverse.
        .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { v in
            guard !m.showPrefs, !m.showSessions else { return }  // sliders and the list own drags there
            if v.translation.height > 12 {
                if m.pinned { m.expanded = true } else { m.pinned = true }
            } else if v.translation.height < -12 {
                if m.expanded { m.expanded = false } else { m.pinned = false }
            }
        })
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: m.size)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    var dot: some View {
        Circle().fill(m.running ? Color.orange : Color.white.opacity(0.3)).frame(width: 6, height: 6)
    }

    var compact: some View {
        HStack(spacing: 6) {
            dot
            Text(m.display).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(.white)
            if m.mode == .countdown && m.completed > 0 { dots(m.completed, cap: 6) }
            if m.mode == .countdown {  // quick start; while running it restarts from the full duration
                Button { m.running ? m.restart() : m.toggle() } label: {
                    Image(systemName: m.running ? "arrow.counterclockwise" : "play.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Color.white.opacity(0.16), in: Circle())
                }.buttonStyle(.plain).padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 26)
        .contentShape(Rectangle())
        .onTapGesture { m.expanded = true }
    }

    var panel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                dot
                Text(m.display).font(.system(size: 34, weight: .light).monospacedDigit()).foregroundStyle(.white)
                Spacer()
                icon("arrow.counterclockwise") { m.reset() }
                icon(m.running ? "pause.fill" : "play.fill", big: true) { m.toggle() }
            }
            .contentShape(Rectangle())
            .onTapGesture { m.expanded = false }

            HStack(spacing: 6) {
                chip("Stopwatch", on: m.mode == .stopwatch) { m.mode = .stopwatch }
                chip("Countdown", on: m.mode == .countdown) { m.mode = .countdown }
                Spacer()
                if m.mode == .countdown {
                    dots(m.completed, cap: 10)
                    chip("Sessions", on: false) { m.showSessions = true }
                }
            }
            if m.mode == .countdown {
                HStack(spacing: 6) {
                    chip("−", on: false) { m.countdownMin = max(1, m.countdownMin - 1) }
                    Text("\(m.countdownMin) min").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8)).frame(width: 46)
                    chip("+", on: false) { m.countdownMin = min(600, m.countdownMin + 1) }
                    Spacer()
                    ForEach([5, 15, 25, 45], id: \.self) { n in
                        chip("\(n)", on: m.countdownMin == n) { m.countdownMin = n }
                    }
                }
            }
            HStack(spacing: 6) {
                chip("♪ \(m.sound) · \(chimeSummary)", on: false) { m.showPrefs = true }
                Spacer()
                icon("gearshape") { m.showPrefs = true }
                icon(m.pinned ? "pin.fill" : "pin") { m.pinned.toggle() }
                icon("power") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    /// One dot per finished countdown.
    func dots(_ n: Int, cap: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(n, cap), id: \.self) { _ in Circle().fill(Color.orange).frame(width: 5, height: 5) }
            if n > cap {
                Text("+\(n - cap)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
            }
        }
    }

    func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' HH:mm" : "d MMM HH:mm"
        return f.string(from: date)
    }

    var sessionsView: some View {
        let done = Array(m.sessions.filter { !$0.minutes.isEmpty }.reversed())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                icon("chevron.left") { m.showSessions = false }
                Text("Sessions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                chip("New session", on: false) { m.newSession() }
                    .opacity(m.completed > 0 ? 1 : 0.35).disabled(m.completed == 0)
                chip("Clear all", on: false) { m.sessions = [Session()] }
                    .opacity(done.isEmpty ? 0.35 : 1).disabled(done.isEmpty)
            }
            if done.isEmpty {
                Text("No finished countdowns yet. Each countdown that reaches zero adds a dot.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(done) { s in
                            let current = s.id == m.sessions.last?.id
                            HStack(spacing: 8) {
                                Text(when(s.start)).font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.white.opacity(current ? 1 : 0.55))
                                    .frame(width: 84, alignment: .leading)
                                dots(s.minutes.count, cap: 16)
                                Spacer()
                                Text("\(s.minutes.reduce(0, +)) min").font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                                Button { m.deleteSession(s.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.5)).frame(width: 16, height: 16)
                                        .background(Color.white.opacity(0.08), in: Circle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
    }

    var chimeSummary: String {
        guard m.chimeEvery > 0 else { return "off" }
        let t = m.chimeEvery < 60 ? "\(m.chimeEvery)s" : "\(m.chimeEvery / 60)m"
        return m.chimeRepeat ? "every \(t)" : "once at \(t)"
    }

    func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).frame(width: 50, alignment: .leading)
    }

    func soundGrid(_ title: String, _ names: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            label(title).padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: names.count, by: 4)), id: \.self) { start in
                    HStack(spacing: 6) {
                        ForEach(names[start..<min(start + 4, names.count)], id: \.self) { name in
                            chip(name, on: (finishTab ? m.doneSound : m.sound) == name) {
                                if finishTab { m.doneSound = name; m.playDone() } else { m.sound = name; m.playChime() }
                            }
                        }
                    }
                }
            }
        }
    }

    var prefs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                icon("chevron.left") { m.showPrefs = false }
                Text("Preferences").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                chip("Chime", on: !finishTab) { finishTab = false }
                chip("Countdown end", on: finishTab) { finishTab = true }
            }
            // "tink" and "glass" are system sounds; offer glass instead of tink for the finish.
            soundGrid("Sound", finishTab ? TimerModel.sounds.map { $0 == "tink" ? "glass" : $0 } : TimerModel.sounds)
            soundGrid("Ring", TimerModel.rings)
            if finishTab {
                HStack(spacing: 6) {
                    label("Volume")
                    Slider(value: $m.doneVolume, in: 0.05...1) { editing in if !editing { m.playDone() } }
                        .controlSize(.mini).tint(.white)
                }
                HStack(spacing: 6) {
                    label("Repeat")
                    chip("Once", on: !m.doneRepeat) { m.doneRepeat = false }
                    chip("Repeating", on: m.doneRepeat) { m.doneRepeat = true }
                }
                Text(m.doneRepeat ? "Rings until you click the timer (1 min at most)."
                                  : "Plays once when a countdown reaches zero.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            } else {
                HStack(spacing: 6) {
                    label("Chime")
                    ForEach([(0, "Off"), (30, "30s"), (60, "1m"), (300, "5m")], id: \.0) { secs, text in
                        chip(text, on: m.chimeEvery == secs) { m.chimeEvery = secs }
                    }
                }
                HStack(spacing: 6) {
                    label("Repeat")
                    chip("Repeating", on: m.chimeRepeat) { m.chimeRepeat = true }
                    chip("Once", on: !m.chimeRepeat) { m.chimeRepeat = false }
                }
                .opacity(m.chimeEvery > 0 ? 1 : 0.35).disabled(m.chimeEvery == 0)
                HStack(spacing: 6) {
                    label("Volume")
                    Slider(value: $m.volume, in: 0.05...1) { editing in if !editing { m.playChime() } }
                        .controlSize(.mini).tint(.white)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.white.opacity(on ? 0.24 : 0.08), in: Capsule())
                .foregroundStyle(.white.opacity(on ? 1 : 0.6))
        }.buttonStyle(.plain)
    }

    func icon(_ name: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: big ? 14 : 11, weight: .semibold))
                .frame(width: big ? 34 : 24, height: big ? 34 : 24)
                .background(Color.white.opacity(big ? 0.16 : 0.08), in: Circle())
                .foregroundStyle(.white)
        }.buttonStyle(.plain)
    }
}

// MARK: - Window

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ r: NSRect, to screen: NSScreen?) -> NSRect { r }  // allow over the menu bar
}

/// Without this the first click on the unfocused panel only focuses it and is swallowed.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = TimerModel()
    var panel: NotchPanel!
    var screen: NSScreen!
    var wasPressed = false, pressInside = false

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = FirstMouseHostingView(rootView: NotchView(m: model))
        host.sizingOptions = []
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.layout() }
        // ponytail: 30Hz cursor poll drives hover + click-through + click-outside. Swap for
        // NSEvent monitors / tracking areas if idle CPU ever shows up in Activity Monitor.
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
    }

    func layout() {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens[0]
        model.notchH = screen.safeAreaInsets.top
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            model.notchW = screen.frame.width - l.width - r.width
        } else {
            model.notchW = 180  // no notch: a thin strip at the top centre stands in for it
        }
        let w: CGFloat = 380, h = model.notchH + 300
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h),
                       display: true)
    }

    func poll() {
        let s = model.size, f = screen.frame
        let rect = NSRect(x: f.midX - s.width / 2 - 2, y: f.maxY - s.height - 2, width: s.width + 4, height: s.height + 4)
        let inside = rect.contains(NSEvent.mouseLocation)
        let pressed = NSEvent.pressedMouseButtons != 0
        if pressed && !wasPressed {
            pressInside = inside
            if !inside { model.expanded = false }  // click elsewhere collapses
        }
        wasPressed = pressed
        if pressed && pressInside { return }  // mid-drag: keep receiving events
        panel.ignoresMouseEvents = !inside
        if model.hovering != inside { model.hovering = inside }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
