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

/// The menu bar clock on each screen. Control Center draws every menu bar item as its own window and the
/// clock is always the rightmost, so it is the item furthest right among those on a screen.
func clockRects(items: [CGRect], screens: [CGRect]) -> [CGRect] {
    screens.compactMap { s in
        items.filter { s.contains(CGPoint(x: $0.midX, y: $0.midY)) }.max { $0.maxX < $1.maxX }
    }
}

/// Which of `n` dots, capped at `cap`, marks the newest session: its index, or nil when the "+N" label stands in for it.
func newestDot(_ n: Int, cap: Int) -> Int? { n > cap ? nil : n - 1 }

/// Starts a new current block from `preset` (unnamed without one) and gives the countdown length that goes with it.
/// Always a new block, never an earlier one resumed; a current block still without sessions is replaced.
func startBlock(from preset: Preset?, in blocks: [Block], countdownMin: Int, now: Date) -> (blocks: [Block], countdownMin: Int) {
    let kept = blocks.last?.minutes.isEmpty == true ? Array(blocks.dropLast()) : blocks
    return (kept + [Block(start: now, name: preset?.name)], preset?.minutes ?? countdownMin)
}

/// A block never spans days: when the current block has sessions from another day, a session finishing `now`
/// lands in a new block from the preset that block was named after, or an unnamed one if there is none (any more).
/// Nil when the current block carries on.
func rollover(_ blocks: [Block], presets: [Preset], countdownMin: Int, now: Date,
              calendar: Calendar = .current) -> (blocks: [Block], countdownMin: Int)? {
    guard let last = blocks.last, !last.minutes.isEmpty, !calendar.isDate(last.start, inSameDayAs: now) else { return nil }
    return startBlock(from: presets.first { $0.name == last.name }, in: blocks, countdownMin: countdownMin, now: now)
}

if CommandLine.arguments.contains("--selftest") {
    let office = Preset(name: "Office", minutes: 40), home = Preset(name: "Home", minutes: 20)
    let day1 = Date(timeIntervalSinceReferenceDate: 800_000_000), day2 = day1 + 86400
    // History written by 0.4 has no names: it loads as unnamed blocks.
    let old = #"[{"id":"7E4A4C0E-0B8B-4E0B-9C61-0C8A1B2C3D4E","start":800000000,"minutes":[25,15]}]"#
    let loaded = (try? JSONDecoder().decode([Block].self, from: Data(old.utf8))) ?? []
    precondition(loaded.count == 1 && loaded[0].name == nil && loaded[0].minutes == [25, 15] && loaded[0].start == day1)
    // Picking a preset: a named block and the preset's length; an empty current block is replaced.
    var picked = startBlock(from: office, in: loaded, countdownMin: 25, now: day1)
    precondition(picked.countdownMin == 40 && picked.blocks.count == 2 && picked.blocks[1].name == "Office")
    picked = startBlock(from: home, in: picked.blocks, countdownMin: 40, now: day1)
    precondition(picked.countdownMin == 20 && picked.blocks.map(\.name) == [nil, "Home"])
    // Office, Home, Office with sessions in each: two separate Office blocks.
    var blocks = [Block(start: day1, minutes: [40], name: "Office"), Block(start: day1, minutes: [20], name: "Home")]
    blocks = startBlock(from: office, in: blocks, countdownMin: 20, now: day1).blocks
    precondition(blocks.map(\.name) == ["Office", "Home", "Office"] && blocks[0].id != blocks[2].id && blocks[0].minutes == [40])
    // "New block": unnamed, countdown length left alone.
    let plain = startBlock(from: nil, in: [Block(start: day1, minutes: [40], name: "Office")], countdownMin: 33, now: day1)
    precondition(plain.countdownMin == 33 && plain.blocks.map(\.name) == ["Office", nil])
    // Day rollover: same day carries on; a new day starts a block from the last-used preset, at its length.
    blocks[2].minutes = [35]
    precondition(rollover(blocks, presets: [office, home], countdownMin: 35, now: day1 + 60) == nil)
    let next = rollover(blocks, presets: [office, home], countdownMin: 35, now: day2)
    precondition(next?.countdownMin == 40 && next?.blocks.count == 4 && next?.blocks.last?.name == "Office"
        && next?.blocks.last?.minutes.isEmpty == true && next?.blocks[2].minutes == [35])
    // Preset deleted, or the last block unnamed: an unnamed block, countdown length left alone.
    let gone = rollover(blocks, presets: [home], countdownMin: 35, now: day2)
    precondition(gone?.countdownMin == 35 && gone?.blocks.count == 4 && gone?.blocks.last?.name == nil)
    let unnamed = rollover(loaded, presets: [office], countdownMin: 25, now: day2)
    precondition(unnamed?.countdownMin == 25 && unnamed?.blocks.count == 2 && unnamed?.blocks.last?.name == nil)
    precondition(rollover([Block(start: day1, name: "Office")], presets: [office], countdownMin: 25, now: day2) == nil)  // nothing finished yet
    precondition(newestDot(1, cap: 5) == 0 && newestDot(5, cap: 5) == 4 && newestDot(6, cap: 5) == nil)
    precondition(format(0) == "00:00" && format(65) == "01:05" && format(3725) == "1:02:05")
    precondition(chimeDue(prev: 29.9, now: 30.1, every: 30))
    precondition(!chimeDue(prev: 30.1, now: 30.3, every: 30))
    precondition(!chimeDue(prev: 0, now: 0.2, every: 30))
    precondition(!chimeDue(prev: 29.9, now: 30.1, every: 0))
    precondition(chimeDue(prev: 29.9, now: 30.1, every: 30, repeats: false))
    precondition(!chimeDue(prev: 59.9, now: 60.1, every: 30, repeats: false))
    let wifi = CGRect(x: 1437, y: 0, width: 38, height: 33), clock = CGRect(x: 1591, y: 0, width: 139, height: 33)
    let clock2 = CGRect(x: 2030, y: -1440, width: 139, height: 30)  // on a second screen above the first
    let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117), external = CGRect(x: -391, y: -1440, width: 2560, height: 1440)
    precondition(clockRects(items: [clock, wifi, clock2], screens: [builtIn, external]) == [clock, clock2])
    precondition(clockRects(items: [clock, wifi], screens: [builtIn, external]) == [clock])  // menu bar hidden on one
    precondition(clockRects(items: [], screens: [builtIn]).isEmpty)
    precondition(Updater.newer("0.10", than: "0.9") && !Updater.newer("0.2", than: "0.2") && !Updater.newer("0.1", than: "0.2"))
    var parsed: SecRequirement?
    precondition(SecRequirementCreateWithString(Updater.requirement as CFString, [], &parsed) == errSecSuccess)
    print("selftest ok")
    exit(0)
}

// MARK: - Updates

/// Self-update from the release bucket: `version` is plain text ("0.2"), `TinyTimer.zip` is the notarized app.
enum Updater {
    static let base = URL(string: "https://dl.yaraoncode.me/tinytimer/")!
    static let download = base.appendingPathComponent("TinyTimer.zip")
    /// Only a bundle signed by this Developer ID team is ever installed.
    static let requirement = """
        identifier "app.tinytimer.TinyTimer" and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "W3U75T8JTH"
        """
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static func newer(_ a: String, than b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }

    /// Calls back on the main queue with the published version, if it is newer than this build.
    static func check(_ found: @escaping (String) -> Void) {
        let req = URLRequest(url: base.appendingPathComponent("version"), cachePolicy: .reloadIgnoringLocalCacheData)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data,
                  let v = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !v.isEmpty, v.count < 20, v.allSatisfy({ $0.isNumber || $0 == "." }),
                  newer(v, than: current) else { return }
            DispatchQueue.main.async { found(v) }
        }.resume()
    }

    /// Download, verify, swap the running bundle and launch the new one. Blocking; throws if any step fails.
    static func install() throws {
        let fm = FileManager.default, app = Bundle.main.bundleURL
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? fm.removeItem(at: dir) }
        let zip = dir.appendingPathComponent("TinyTimer.zip")
        try Data(contentsOf: download).write(to: zip)
        try run("/usr/bin/ditto", "-x", "-k", zip.path, dir.path)
        let new = dir.appendingPathComponent("TinyTimer.app")
        // Trust boundary: the download must be signed by our team and must not be a downgrade.
        var code: SecStaticCode?, req: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCreateWithPath(new as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req,
              SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess,
              let v = Bundle(url: new)?.infoDictionary?["CFBundleShortVersionString"] as? String,
              newer(v, than: current) else { throw CocoaError(.fileReadCorruptFile) }
        _ = try fm.replaceItemAt(app, withItemAt: new)
        try run("/usr/bin/open", "-n", app.path)
    }

    private static func run(_ path: String, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}

// MARK: - Model

/// A stretch of work within one day. The last element of `blocks` is the current one.
struct Block: Codable, Identifiable {
    var id = UUID()
    var start = Date()
    var minutes: [Int] = []  // length of each session (finished countdown); one dot each
    var name: String?  // the preset it was started from; nil for an unnamed block and for history from before 0.5
}

/// A saved name and countdown length from which blocks are started. Found again by name, so names are unique.
struct Preset: Codable { var name: String; var minutes: Int }

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
    // Stored under "sessions", the key from before blocks had a name of their own.
    @Published var blocks: [Block] { didSet { d.set(try? JSONEncoder().encode(blocks), forKey: "sessions") } }
    @Published var presets: [Preset] { didSet { d.set(try? JSONEncoder().encode(presets), forKey: "presets") } }
    var completed: Int { blocks.last?.minutes.count ?? 0 }  // sessions in the current block
    @Published var doneRepeat: Bool { didSet { d.set(doneRepeat, forKey: "doneRepeat") } }
    /// Preference: cover the menu bar clock while the timer runs (either mode), so there is no time to glance at.
    @Published var hideClock: Bool { didSet { d.set(hideClock, forKey: "hideClock") } }
    static let sounds = ["bell", "chime", "bowl", "kalimba", "marimba", "wood", "drop", "tink"]  // single hits
    static let rings = ["phone", "digital", "melody", "bells", "pulse", "harp"]  // ringtone-style patterns

    /// A countdown finished and the user has not hovered over or clicked the timer since. Never persisted.
    @Published var finishUnacknowledged = false
    @Published var expanded = false {
        didSet { if expanded { stopRinging() } else { showPrefs = false; showSessions = false } }
    }
    @Published var showSessions = false
    @Published var update: String?  // newer published version, if any
    @Published var updating = false
    @Published var showPrefs = false
    @Published var hovering = false { didSet { if hovering { acknowledgeFinish() } } }
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
        blocks = d.data(forKey: "sessions").flatMap { try? JSONDecoder().decode([Block].self, from: $0) } ?? []
        presets = d.data(forKey: "presets").flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? []
        doneRepeat = d.bool(forKey: "doneRepeat")
        hideClock = d.bool(forKey: "hideClock")
        if blocks.isEmpty {  // first run; carry over the old plain counter if there was one
            blocks = [Block(minutes: Array(repeating: countdownMin, count: d.integer(forKey: "completed")))]
        }
        startFreshIfStale()
        loadChime()
        loadDone()
    }

    var duration: TimeInterval { TimeInterval(countdownMin * 60) }
    var display: String {
        mode == .stopwatch ? format(Int(elapsed)) : format(Int(max(0, duration - elapsed).rounded(.up)))
    }
    var shown: Bool { pinned || hovering || expanded || finishUnacknowledged }
    /// Size of the black shape hanging from the top edge (includes the notch itself).
    var size: CGSize {
        if showPrefs || showSessions { return CGSize(width: max(notchW, 340), height: notchH + (showPrefs ? 288 : 256)) }
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

    /// Yesterday's block doesn't continue today.
    private func startFreshIfStale() {
        guard let r = rollover(blocks, presets: presets, countdownMin: countdownMin, now: Date()) else { return }
        blocks = r.blocks; countdownMin = r.countdownMin
    }

    /// Picking a preset, or "New block" without one.
    func newBlock(from preset: Preset? = nil) {
        (blocks, countdownMin) = startBlock(from: preset, in: blocks, countdownMin: countdownMin, now: Date())
    }

    /// Saves the countdown length now set under `name`. False if the name is empty or already taken.
    func savePreset(_ name: String) -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespaces).prefix(16))  // has to fit the panel's chip
        guard !name.isEmpty, !presets.contains(where: { $0.name == name }) else { return false }
        presets.append(Preset(name: name, minutes: countdownMin))
        return true
    }

    func deleteBlock(_ id: UUID) {
        let name = blocks.last?.name
        blocks.removeAll { $0.id == id }
        if blocks.last?.minutes.isEmpty != true { blocks.append(Block(name: name)) }  // keep an open current block
    }

    private func recordFinish() {
        let ran = countdownMin  // a new day's block may change the length for the next countdown, not for this session
        startFreshIfStale()
        var all = blocks
        if all[all.count - 1].minutes.isEmpty { all[all.count - 1].start = Date() }
        all[all.count - 1].minutes.append(ran)
        // ponytail: history lives in UserDefaults, capped at 200 blocks; move to a file if it needs to grow.
        blocks = Array(all.suffix(200))
    }

    func checkForUpdate() { Updater.check { [weak self] v in self?.update = v } }

    /// Installs the update and quits; if that fails (e.g. read-only location), opens the download instead.
    func installUpdate() {
        guard !updating else { return }
        updating = true
        DispatchQueue.global().async {
            let ok = (try? Updater.install()) != nil
            DispatchQueue.main.async {
                if ok { NSApp.terminate(nil) } else { self.updating = false; NSWorkspace.shared.open(Updater.download) }
            }
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.stopRinging(acknowledge: false) }
    }
    func acknowledgeFinish() { if finishUnacknowledged { finishUnacknowledged = false } }
    /// Every interaction that dismisses the ring also acknowledges the finish; the 60s cap does not.
    func stopRinging(acknowledge: Bool = true) {
        if acknowledge { acknowledgeFinish() }
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
            finishUnacknowledged = true
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
    @State private var addingPreset = false  // Sessions: the name field for a new preset is open
    @State private var presetName = ""
    @FocusState private var namingPreset: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            if m.mode == .countdown && m.completed > 0 { dots(m.completed, cap: 5, pulse: m.finishUnacknowledged) }
            if m.mode == .countdown {  // quick start; while running it restarts from the full duration
                mini(m.running ? "arrow.counterclockwise" : "play.fill") { m.running ? m.restart() : m.toggle() }
                    .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 26)
        .contentShape(Rectangle())
        // Pin sits in the right corner so the timer stays centred. Unpinned, the strip is only
        // here while hovered, so it slides away once the mouse leaves.
        .overlay(alignment: .trailing) {
            Button { m.pinned.toggle() } label: {
                Image(systemName: m.pinned ? "pin.fill" : "pin").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45)).frame(width: 22, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.trailing, 5).help(m.pinned ? "Unpin" : "Pin")
        }
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
                    dots(m.completed, cap: 10, pulse: m.finishUnacknowledged)
                    chip(m.blocks.last?.name ?? "Sessions", on: false) { m.showSessions = true }
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
                if let v = m.update {  // takes the sound chip's place; the gear still opens Preferences
                    chip(m.updating ? "Updating…" : "Update to \(v)", on: true) { m.installUpdate() }
                } else {
                    chip("♪ \(m.sound) · \(chimeSummary)", on: false) { m.showPrefs = true }
                }
                Spacer()
                icon("gearshape") { m.showPrefs = true }
                icon(m.pinned ? "pin.fill" : "pin") { m.pinned.toggle() }
                icon("power") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    /// One dot per finished countdown. With `pulse`, the newest dot (or the "+N" label standing in for it) pulses.
    func dots(_ n: Int, cap: Int, pulse: Bool = false) -> some View {
        let newest = pulse ? newestDot(n, cap: cap) : -1
        return HStack(spacing: 3) {
            ForEach(0..<min(n, cap), id: \.self) { i in
                pulsing(Circle().frame(width: 5, height: 5), i == newest)
            }
            if n > cap {
                pulsing(Text("+\(n - cap)").font(.system(size: 9, weight: .semibold)), newest == nil)
            }
        }
    }

    /// Orange like every dot; when `on` it pulses, or with Reduce Motion is only highlighted in white.
    @ViewBuilder func pulsing<V: View>(_ v: V, _ on: Bool) -> some View {
        if on && !reduceMotion {
            v.foregroundStyle(.orange).phaseAnimator([true, false]) { c, lit in
                c.opacity(lit ? 1 : 0.25).scaleEffect(lit ? 1.3 : 1)
            } animation: { _ in .easeInOut(duration: 0.6) }
        } else {
            v.foregroundStyle(on ? .white : .orange)
        }
    }

    func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' HH:mm" : "d MMM HH:mm"
        return f.string(from: date)
    }

    func savePreset() {
        if m.savePreset(presetName) { presetName = ""; addingPreset = false }
    }

    func remove(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5)).frame(width: 16, height: 16)
                .background(Color.white.opacity(0.08), in: Circle())
        }.buttonStyle(.plain)
    }

    var sessionsView: some View {
        let done = Array(m.blocks.filter { !$0.minutes.isEmpty }.reversed())
        let current = m.blocks.last
        let fresh = current?.minutes.isEmpty == true && current?.name == nil  // already an empty unnamed block
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                icon("chevron.left") { m.showSessions = false }
                Text("Sessions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                chip("+", on: addingPreset) { addingPreset.toggle() }.help("Save a preset")
                chip("New block", on: false) { m.newBlock() }
                    .opacity(fresh ? 0.35 : 1).disabled(fresh)
                chip("Clear all", on: false) { m.blocks = [Block(name: current?.name)] }
                    .opacity(done.isEmpty ? 0.35 : 1).disabled(done.isEmpty)
            }
            if addingPreset {
                HStack(spacing: 6) {
                    TextField("Preset name", text: $presetName).textFieldStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(.white).environment(\.colorScheme, .dark)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .focused($namingPreset).onSubmit { savePreset() }
                        // The panel never activates the app; it has to be key for the field to get the typing.
                        .onAppear { NSApp.windows.first { $0 is NotchPanel }?.makeKey(); namingPreset = true }
                    chip("Save · \(m.countdownMin) min", on: true) { savePreset() }
                }
            }
            if !m.presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(m.presets, id: \.name) { p in
                            HStack(spacing: 2) {
                                chip("\(p.name) · \(p.minutes)", on: current?.name == p.name) { m.newBlock(from: p) }
                                remove { m.presets.removeAll { $0.name == p.name } }
                            }
                        }
                    }
                }
            }
            if done.isEmpty {
                Text("No finished countdowns yet. Each countdown that reaches zero adds a dot.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(done) { s in
                            let on = s.id == current?.id
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    if let name = s.name {
                                        Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                            .foregroundStyle(.white.opacity(on ? 1 : 0.7))
                                    }
                                    Text(when(s.start)).font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(.white.opacity(on ? 1 : 0.55))
                                }
                                .frame(width: 84, alignment: .leading)
                                dots(s.minutes.count, cap: 16)
                                Spacer()
                                Text("\(s.minutes.reduce(0, +)) min").font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                                remove { m.deleteBlock(s.id) }
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
            HStack(spacing: 6) {  // not a sound setting, so it shows under both tabs
                label("Clock")
                chip("Always shown", on: !m.hideClock) { m.hideClock = false }
                chip("Hidden while timing", on: m.hideClock) { m.hideClock = true }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.white.opacity(on ? 0.24 : 0.08), in: Capsule())
                .foregroundStyle(.white.opacity(on ? 1 : 0.6))
        }.buttonStyle(.plain)
    }

    /// Small round button for the compact strip.
    func mini(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Color.white.opacity(0.16), in: Circle())
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

/// Hides the menu bar clock by laying a blurred patch over it on every screen. macOS has no way to
/// switch the clock off, and covering it changes no system setting, so there is nothing to restore
/// after a quit or a crash. Clicks pass through to the clock underneath.
final class ClockCover {
    private var covers: [NSPanel] = []
    private var hidden = false, lastLook = Date.distantPast

    /// Call often. Covers the clock the moment `hide` turns on and uncovers it the moment it turns off.
    /// ponytail: while hidden the clock is looked up again once a second, because it moves when menu bar
    /// items come and go and leaves with the menu bar in full screen; one that reappears can show for up
    /// to a second. Watch the window list for changes instead if that second ever matters.
    func tick(hide: Bool) {
        guard hide != hidden || (hide && Date().timeIntervalSince(lastLook) >= 1) else { return }
        hidden = hide
        lastLook = Date()
        let rects = hide ? Self.clocks() : []
        while covers.count < rects.count { covers.append(Self.cover()) }
        for (i, c) in covers.enumerated() {
            if i < rects.count { c.setFrame(rects[i], display: true); c.orderFrontRegardless() } else { c.orderOut(nil) }
        }
    }

    /// Where the clocks are now, in AppKit screen coordinates. Needs no permission: only window
    /// owners, layers and bounds are read, never their names or contents.
    private static func clocks() -> [NSRect] {
        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let items = list
            .filter { $0[kCGWindowOwnerPID as String] as? pid_t == controlCenter.processIdentifier
                && $0[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .filter { $0.height < 50 }  // menu bar items only, not a panel opened from one
        // The window list measures y down from the top of the primary screen, AppKit up from its bottom.
        let top = NSScreen.screens[0].frame.maxY
        let flip = { (r: CGRect) in CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
        return clockRects(items: items, screens: NSScreen.screens.map { flip($0.frame) }).map(flip)
    }

    private static func cover() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI  // the closest match to the menu bar of the materials tried
        blur.blendingMode = .behindWindow
        blur.state = .active
        // Fade the left edge in, so the patch has no hard seam next to the neighbouring item. The fade
        // stays inside the clock's own padding (its text starts 8pt in), or the first letter shows through.
        let fade = NSImage(size: NSSize(width: 12, height: 8), flipped: false) { r in
            NSGradient(starting: .clear, ending: .black)?.draw(in: NSRect(x: 0, y: 0, width: 6, height: r.height), angle: 0)
            NSColor.black.setFill()
            NSRect(x: 6, y: 0, width: 6, height: r.height).fill()
            return true
        }
        fade.capInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 1)
        fade.resizingMode = .stretch
        blur.maskImage = fade
        p.contentView = blur
        return p
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = TimerModel()
    let clockCover = ClockCover()
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
        model.checkForUpdate()
        let daily = Timer(timeInterval: 86400, repeats: true) { [weak self] _ in self?.model.checkForUpdate() }
        RunLoop.main.add(daily, forMode: .common)
        // ponytail: 30Hz poll drives hover + click-through + click-outside + the clock cover. Swap for
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
        clockCover.tick(hide: model.hideClock && model.running)
        let s = model.size, f = screen.frame
        let rect = NSRect(x: f.midX - s.width / 2 - 2, y: f.maxY - s.height - 2, width: s.width + 4, height: s.height + 4)
        let inside = rect.contains(NSEvent.mouseLocation)
        let pressed = NSEvent.pressedMouseButtons != 0
        if pressed && !wasPressed {
            pressInside = inside
            if inside { model.acknowledgeFinish() } else { model.expanded = false }  // click elsewhere collapses
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
