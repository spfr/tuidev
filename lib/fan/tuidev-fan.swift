// lib/fan/tuidev-fan.swift — fan control for Apple Silicon Macs (the cooling pack).
//
// Owns: the SMC connection (AppleSMC, through IOKit), reading the fans and the
//   SoC's die temperature, taking and releasing manual fan control, the fan
//   curve, the daemon that applies it, and installing that daemon.
// Commands:
//   status [--tsv]       fans and SoC temperature (no root needed)
//   try [RPM] [SECS]     root: hold RPM for SECS, report whether macOS takes the
//                        fans back, then release them (a one-off hardware check)
//   release              root: hand every fan back to macOS
//   install | uninstall  root: copy this binary to a root-owned path and run it
//                        as a LaunchDaemon (Paths), or stop and remove it
//   daemon               root: the thermostat the LaunchDaemon runs
//   curve TEMP [PRESSURE] [MODE LOW HIGH MIN MAX PREVIOUS]
//                        the RPM the curve asks for, or "macos" (no hardware:
//                        the tests run it)
//
// Apple has no public fan API: this writes the SMC keys the established fan
// tools write (F<n>Md mode, F<n>Tg target). The mode write is tried directly
// and read back; where the firmware refuses it (some M1–M4 Macs) the Ftst
// diagnostic flag is set first. Stats (github.com/exelban/stats, MIT)
// documents the same sequence.
//
// Safety: a fan is taken only when the curve asks for more than macOS runs it
// at, and never set below its own minimum; heavy thermal pressure means full
// speed. Every failure, exit signal and system sleep hands the fans back to
// macOS, and the daemon releases them when it starts (launchd restarts it
// after a crash). The SoC's own thermal protection keeps working underneath.
//
// Build: swiftc -O -swift-version 5 lib/fan/tuidev-fan.swift -o tuidev-fan

import Foundation
import IOKit
import IOKit.pwr_mgt
import notify

// MARK: - SMC

/// The struct AppleSMC's user client takes (selector 2), field for field.
struct SMCParam {
    struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    struct Info { var size: UInt32 = 0; var type: UInt32 = 0; var attributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers = Vers()
    var pLimit = PLimit()
    var info = Info()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var index: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

enum SMCError: Error, CustomStringConvertible {
    case unavailable(String)
    case call(String, kern_return_t)
    case firmware(String, UInt8)
    case notFound(String)
    case badValue(String)

    var description: String {
        switch self {
        case .unavailable(let why): return "AppleSMC unavailable: \(why)"
        case .call(let key, let r): return "\(key): IOKit error 0x\(String(UInt32(bitPattern: r), radix: 16))"
        case .firmware(let key, let r): return "\(key): the SMC refused it (0x\(String(r, radix: 16)))"
        case .notFound(let key): return "\(key): no such key"
        case .badValue(let key): return "\(key): unexpected type or size"
        }
    }
}

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func fourCCString(_ v: UInt32) -> String {
    String(decoding: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], as: UTF8.self)
}

final class SMC {
    private static let selector: UInt32 = 2
    private enum Command: UInt8 { case readBytes = 5, writeBytes = 6, readIndex = 8, readInfo = 9 }
    private var conn: io_connect_t = 0
    private var infoCache: [UInt32: SMCParam.Info] = [:]
    /// One SMC call at a time: `try`'s signal handler releases from its own
    /// queue, holding this until it exits.
    let lock = NSRecursiveLock()

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.unavailable("no AppleSMC service") }
        defer { IOObjectRelease(service) }
        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard r == kIOReturnSuccess else { throw SMCError.call("open", r) }
    }

    deinit { IOServiceClose(conn) }

    private func call(_ input: inout SMCParam, _ key: String) throws -> SMCParam {
        lock.lock(); defer { lock.unlock() }
        var output = SMCParam()
        var size = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(conn, SMC.selector, &input, MemoryLayout<SMCParam>.stride, &output, &size)
        guard r == kIOReturnSuccess else { throw SMCError.call(key, r) }
        if output.result == 0x84 { throw SMCError.notFound(key) }
        guard output.result == 0 else { throw SMCError.firmware(key, output.result) }
        return output
    }

    private func info(_ key: String) throws -> SMCParam.Info {
        lock.lock(); defer { lock.unlock() }
        let code = fourCC(key)
        if let cached = infoCache[code] { return cached }
        var input = SMCParam()
        input.key = code
        input.command = Command.readInfo.rawValue
        let info = try call(&input, key).info
        infoCache[code] = info
        return info
    }

    func exists(_ key: String) -> Bool { (try? info(key)) != nil }

    /// The key's SMC type ("flt ", "ui8 "…) and its bytes.
    func read(_ key: String) throws -> (type: String, bytes: [UInt8]) {
        let info = try info(key)
        var input = SMCParam()
        input.key = fourCC(key)
        input.info.size = info.size
        input.command = Command.readBytes.rawValue
        let output = try call(&input, key)
        let all = withUnsafeBytes(of: output.bytes) { Array($0) }
        return (fourCCString(info.type), Array(all.prefix(Int(min(info.size, 32)))))
    }

    func write(_ key: String, _ bytes: [UInt8]) throws {
        let info = try info(key)
        guard bytes.count == Int(info.size) else { throw SMCError.badValue(key) }
        var input = SMCParam()
        input.key = fourCC(key)
        input.info.size = info.size
        input.command = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { dst in
            for (i, b) in bytes.enumerated() { dst[i] = b }
        }
        _ = try call(&input, key)
    }

    func number(_ key: String) throws -> Double {
        let (type, b) = try read(key)
        switch type {
        case "flt " where b.count >= 4: return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 " where b.count >= 1: return Double(b[0])
        case "ui16" where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4: return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "fpe2" where b.count >= 2: return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
        default: throw SMCError.badValue(key)
        }
    }

    /// Every key name, by index (#KEY holds how many).
    func keys() throws -> [String] {
        let n = Int(try number("#KEY"))
        var names: [String] = []
        names.reserveCapacity(n)
        for i in 0..<n {
            var input = SMCParam()
            input.command = Command.readIndex.rawValue
            input.index = UInt32(i)
            if let out = try? call(&input, "#\(i)") { names.append(fourCCString(out.key)) }
        }
        return names
    }
}

// MARK: - Fans and sensors

struct Fan {
    let id: Int
    var actual: Double
    var target: Double
    var min: Double
    var max: Double
    var manual: Bool

    /// A fan the daemon may drive: a sane, finite range. Anything else (an
    /// uninitialised key reading 0 or NaN) is left to macOS.
    var controllable: Bool { min.isFinite && max.isFinite && min > 0 && max > min && max < 20_000 }
    /// What macOS runs it at now (its target, or the actual speed if higher).
    var current: Double { Swift.max(actual.isFinite ? actual : 0, target.isFinite ? target : 0) }
}

/// Int(x) traps on NaN and infinity; status lines must never crash the daemon.
func whole(_ x: Double) -> Int { x.isFinite ? Int(x.rounded()) : 0 }

final class Machine {
    let smc: SMC
    /// The SoC's die sensors: performance cores (Tp*), efficiency cores (Te*)
    /// and GPU (Tg*), the same key families on every M-series chip. Found
    /// once, by enumeration.
    private(set) lazy var dieKeys: [String] = {
        ((try? smc.keys()) ?? []).filter { k in
            (k.hasPrefix("Tp") || k.hasPrefix("Te") || k.hasPrefix("Tg")) && ((try? smc.read(k).type) == "flt ")
        }
    }()
    private lazy var modeKey: (Int) -> String = {
        // Most Apple Silicon Macs spell the mode key F0Md; some spell it F0md.
        let lower = !smc.exists("F0Md") && smc.exists("F0md")
        return { lower ? "F\($0)md" : "F\($0)Md" }
    }()

    init() throws { smc = try SMC() }

    var fanCount: Int { Int((try? smc.number("FNum")) ?? 0) }

    func fan(_ id: Int) throws -> Fan {
        Fan(id: id,
            actual: try smc.number("F\(id)Ac"),
            target: try smc.number("F\(id)Tg"),
            min: try smc.number("F\(id)Mn"),
            max: try smc.number("F\(id)Mx"),
            manual: try smc.number(modeKey(id)) == 1)
    }

    func fans() throws -> [Fan] { try (0..<fanCount).map { try fan($0) } }

    /// The hottest CPU or GPU core in °C, ignoring sensors that read nonsense.
    func socTemperature() throws -> Double {
        let values = dieKeys.compactMap { try? smc.number($0) }.filter { $0 > 10 && $0 < 130 }
        guard let hottest = values.max() else { throw SMCError.unavailable("no SoC temperature sensor answered") }
        return hottest
    }

    static let pressureName = "com.apple.system.thermalpressurelevel"
    private lazy var pressureToken: Int32? = {
        var token: Int32 = 0
        return notify_register_check(Machine.pressureName, &token) == NOTIFY_STATUS_OK ? token : nil
    }()

    /// The kernel's thermal pressure: 0 nominal, 1 moderate, 2 heavy, 3
    /// trapping, 4 sleeping; nil when it can't be read.
    func thermalPressure() -> Int? {
        guard let token = pressureToken else { return nil }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return nil }
        return Int(state)
    }

    // Writing: root only.

    private func retry(_ attempts: Int, delay: useconds_t, _ body: () throws -> Void) throws {
        var last: Error = SMCError.unavailable("never tried")
        for attempt in 0..<attempts {
            do { try body(); return } catch { last = error }
            if attempt < attempts - 1 { usleep(delay) }
        }
        throw last
    }

    /// Put fan ID under manual control: directly (M5), else with Ftst set first
    /// (M1–M4), which makes thermalmonitord yield the fans after a moment.
    /// Bounded: about 6 s at worst, so a stop signal waiting behind it is
    /// handled well inside launchd's exit timeout.
    func takeControl(_ id: Int) throws {
        let key = modeKey(id)
        if (try? smc.write(key, [1])) != nil, (try? smc.number(key)) == 1 { return }
        guard smc.exists("Ftst") else { throw SMCError.firmware(key, 0) }
        if try smc.number("Ftst") != 1 {
            try retry(20, delay: 50_000) { try smc.write("Ftst", [1]) }
            usleep(3_000_000)
        }
        try retry(20, delay: 100_000) {
            try smc.write(key, [1])
            guard try smc.number(key) == 1 else { throw SMCError.firmware(key, 0xfd) }
        }
    }

    func setTarget(_ id: Int, rpm: Double) throws {
        let (type, _) = try smc.read("F\(id)Tg")
        guard type == "flt " else { throw SMCError.badValue("F\(id)Tg") }
        try retry(10, delay: 50_000) { try smc.write("F\(id)Tg", Float(rpm).bytes) }
    }

    /// Hand every fan back to macOS: automatic mode, then Ftst cleared.
    func release() throws {
        var failure: Error?
        for id in 0..<fanCount {
            let key = modeKey(id)
            do {
                if try smc.number(key) != 0 { try retry(10, delay: 50_000) { try smc.write(key, [0]) } }
            } catch { failure = error }
        }
        if smc.exists("Ftst"), (try? smc.number("Ftst")) != 0 {
            do { try retry(10, delay: 50_000) { try smc.write("Ftst", [0]) } } catch { failure = error }
        }
        if let failure { throw failure }
    }
}

extension Float {
    var bytes: [UInt8] { withUnsafeBytes(of: self) { Array($0) } }
}

// MARK: - The curve

/// Settings the daemon reads every tick; out-of-range values fall back to
/// the defaults, so a bad file can never make the fans quieter than macOS.
struct Settings {
    /// cool, auto (balanced) and quiet follow the curve over their own range
    /// of the sustained temperature; max runs the fans flat out; off leaves
    /// them to macOS.
    enum Mode: String {
        case cool, auto, quiet, max, off
        var follows: Bool { self == .cool || self == .auto || self == .quiet }
        /// The range a preset fixes: cool keeps palms cool (the palm rest
        /// starts to feel warm from about 75 °C sustained on an M4 Pro),
        /// quiet lets the chassis warm before the fans work. auto's comes
        /// from fan.conf.
        var preset: (low: Double, high: Double)? {
            switch self {
            case .cool: return (55, 85)
            case .quiet: return (70, 100)
            default: return nil
            }
        }
    }
    var mode: Mode = .auto
    /// Below `low` °C the fans are macOS's; from `low` to `high` the curve
    /// rises from the fan's minimum to its maximum.
    var low: Double = 60
    var high: Double = 95

    /// At most 4 KB of a settings file: both are tiny, and an admin process
    /// growing one must not grow the daemon.
    static func small(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 4096) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func load(from dir: URL) -> Settings {
        var s = Settings()
        if let text = small(dir.appendingPathComponent("mode")),
           let mode = Mode(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            s.mode = mode
        }
        if let text = small(dir.appendingPathComponent("fan.conf")) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, !parts[0].hasPrefix("#"), let v = Double(parts[1]) else { continue }
                switch parts[0] {
                case "low": s.low = v
                case "high": s.high = v
                default: break
                }
            }
        }
        // A curve that starts above 75 °C would hold fans slower than macOS
        // runs them hot: refused, like anything else out of range.
        if !(40...75).contains(s.low) { s.low = 60 }
        if !(s.low + 5...105).contains(s.high) { s.high = max(95, s.low + 5) }
        if let p = s.mode.preset { (s.low, s.high) = p }
        return s
    }
}

/// What the curve reads: the hottest core, smoothed, rising with one time
/// constant and falling with another. A single core's burst moves the
/// hottest sensor 15 °C in a second; followed raw, the fans surge and
/// settle all day.
///
/// The daemon keeps two. `sustained` (60 s up, 180 s down) is what the palm
/// rest and keyboard feel: the chassis soaks up power over minutes, and no
/// SMC sensor sits under your hands (a palm test on an M4 Pro moved none by
/// more than 0.5 °C), so the fans follow it and settle at a steady speed.
/// `prompt` (9 s up, 40 s down) takes over when the chip itself needs air:
/// at moderate thermal pressure, or within 5 °C of the curve's top.
struct Smoother {
    let rise: Double
    let fall: Double
    private(set) var value: Double?

    static func sustained() -> Smoother { Smoother(rise: 60, fall: 180) }
    static func prompt() -> Smoother { Smoother(rise: 9, fall: 40) }

    mutating func add(_ temp: Double, after seconds: Double) -> Double {
        guard let v = value else { value = temp; return temp }
        let a = 1 - exp(-Swift.max(seconds, 0) / (temp > v ? rise : fall))
        let next = v + a * (temp - v)
        value = next
        return next
    }
}

struct Curve {
    /// Degrees below `low` the SoC must reach before the fans go back to
    /// macOS, so they don't flap at the threshold.
    static let hysteresis = 5.0
    /// The most the target may fall per tick, on top of the smoothing.
    static let maxDrop = 150.0
    /// A new target smaller than this away from the current one is left
    /// alone (except at the fan's maximum): nobody hears it, and every change
    /// is a ramp the fan has to make.
    static let deadband = 150.0

    /// The RPM to hold for `fan`, or nil to leave it to macOS. `temp` is the
    /// smoothed temperature, `raw` the hottest core now. In auto, heavy
    /// thermal pressure (2 or more) or a raw reading at `high` runs the fans
    /// at full speed at once, smoothing or not.
    static func target(_ s: Settings, temp: Double, raw: Double? = nil, pressure: Int?, engaged: Bool, fan: Fan, previous: Double?) -> Double? {
        switch s.mode {
        case .off: return nil
        case .max: return fan.max
        case .cool, .auto, .quiet:
            if let pressure, pressure >= 2 { return fan.max }
            if let raw, raw >= s.high { return fan.max }
            if temp < s.low - (engaged ? hysteresis : 0) { return nil }
            let share = s.high > s.low ? Swift.min(Swift.max((temp - s.low) / (s.high - s.low), 0), 1) : 1
            var rpm = fan.min + share * (fan.max - fan.min)
            if let previous { rpm = Swift.max(rpm, previous - maxDrop) }
            return Swift.min(Swift.max(rpm, fan.min), fan.max).rounded()
        }
    }
}

// MARK: - Commands

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("tuidev-fan: \(message)\n".utf8))
    exit(code)
}

func requireRoot() {
    guard geteuid() == 0 else { fail("this needs root (sudo)", code: 2) }
}

func status(_ m: Machine, tsv: Bool) throws {
    let temp = try? m.socTemperature()
    let fans = try m.fans()
    if tsv {
        print("soc\t\(temp.map { String(format: "%.1f", $0) } ?? "-")")
        for f in fans {
            print("fan\t\(f.id)\t\(whole(f.actual))\t\(whole(f.target))\t\(whole(f.min))\t\(whole(f.max))\t\(f.manual ? "manual" : "auto")")
        }
        return
    }
    print("SoC: \(temp.map { String(format: "%.1f °C", $0) } ?? "unknown") (hottest of \(m.dieKeys.count) CPU and GPU sensors)")
    if fans.isEmpty { print("no fans") }
    for f in fans {
        print("fan \(f.id): \(whole(f.actual)) rpm (target \(whole(f.target)), range \(whole(f.min))–\(whole(f.max))), \(f.manual ? "manual" : "macOS")")
    }
}

/// Take the fans, hold RPM for SECS seconds while watching for macOS taking
/// them back (re-taking each time), then release them.
func tryHold(_ m: Machine, rpm requested: Double?, seconds: Int) throws {
    requireRoot()
    guard launchctl("print", "system/\(Paths.label)") != 0 else {
        fail("the dev.tuidev.fan daemon runs the fans; stop it first: launchctl bootout system/\(Paths.label)", code: 2)
    }
    let fans = try m.fans()
    guard !fans.isEmpty else { fail("this Mac has no fans") }
    // Holding the SMC's lock while releasing and exiting: the main thread
    // can't take a fan back in between.
    onExitSignal { m.smc.lock.lock(); try? m.release(); print("interrupted: fans released to macOS") }
    let rpm = requested ?? (fans[0].min + fans[0].max) / 2
    print("taking the fans, holding \(whole(rpm)) rpm for \(seconds)s…")
    for f in fans {
        try m.takeControl(f.id)
        try m.setTarget(f.id, rpm: min(max(rpm, f.min), f.max))
    }
    var reverts = 0
    for second in 1...seconds {
        sleep(1)
        for f in try m.fans() {
            if !f.manual {
                reverts += 1
                print("  \(second)s fan \(f.id): macOS took it back; taking it again")
                try m.takeControl(f.id)
                try m.setTarget(f.id, rpm: min(max(rpm, f.min), f.max))
            }
        }
        if second % 5 == 0 || second == seconds {
            let line = try m.fans().map { "fan \($0.id) \(whole($0.actual)) rpm\($0.manual ? "" : " (macOS)")" }.joined(separator: ", ")
            print("  \(second)s \(line), SoC \(String(format: "%.0f", (try? m.socTemperature()) ?? 0)) °C")
        }
    }
    try m.release()
    print("released the fans to macOS. macOS took them back \(reverts) time(s) in \(seconds)s.")
    print(reverts == 0 ? "result: manual control holds on this Mac." : "result: manual control holds only while re-asserted (the daemon does that every tick).")
}

/// On SIGINT/SIGTERM/SIGHUP, run `body` (which releases the fans) and exit.
/// `try` sleeps on the main thread, so its handlers run on a queue of their
/// own (the SMC's lock keeps their calls apart); the daemon's run on main.
var exitSources: [DispatchSourceSignal] = []
func onExitSignal(queue: DispatchQueue = DispatchQueue(label: "tuidev-fan.signals"), _ body: @escaping () -> Void) {
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
        src.setEventHandler { body(); exit(0) }
        src.resume()
        exitSources.append(src)
    }
}

// MARK: - Daemon

final class Daemon {
    /// Seconds between readings while the fans are ours or the SoC is
    /// within 10 °C of the curve, and while it is cool and the fans macOS's.
    static let busyInterval = 2.0
    static let idleInterval = 10.0
    static let backoff = 300.0

    let m: Machine
    let dir: URL
    var settings: Settings
    var engaged = false
    var targets: [Int: Double] = [:]
    var sustained = Smoother.sustained()
    var prompt = Smoother.prompt()
    /// What the curve used last: sustained, or prompt when the chip needs it.
    var smoothed: Double? { usingPrompt ? prompt.value : sustained.value }
    var usingPrompt = false
    var lastTick: Date?
    var raw: Double?
    var reverts = 0
    var failures = 0
    var hotStreak = 0
    var backoffUntil: Date?
    var lastError = ""
    var interval = Daemon.busyInterval
    let timer = DispatchSource.makeTimerSource(queue: .main)
    var watchers: [String: DispatchSourceFileSystemObject] = [:]
    var pressureToken: Int32 = 0
    var powerPort: IONotificationPortRef?
    var powerNotifier: io_object_t = 0
    var rootPort: io_connect_t = 0

    init(_ m: Machine, dir: URL) {
        self.m = m
        self.dir = dir
        settings = Settings.load(from: dir)
    }

    func releaseAll(_ why: String) {
        do { try m.release(); lastError = why } catch { lastError = "release failed: \(error)" }
        engaged = false
        targets.removeAll()
    }

    /// One reading and, when it calls for it, one change: the SoC's
    /// temperature, the fans once, the curve, then the status file.
    func tick() {
        let now = Date()
        if let until = backoffUntil, now < until {
            writeStatus(temp: smoothed, pressure: m.thermalPressure(), fans: (try? m.fans()) ?? [])
            return
        }
        backoffUntil = nil
        let pressure = m.thermalPressure()
        let temp: Double
        do {
            let t = try m.socTemperature()
            raw = t
            let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
            let slow = sustained.add(t, after: dt)
            let fast = prompt.add(t, after: dt)
            usingPrompt = (pressure ?? 0) >= 1 || fast >= settings.high - 5
            temp = usingPrompt ? Swift.max(slow, fast) : slow
        } catch {
            raw = nil
            if engaged { releaseAll("no temperature: \(error)") }
            lastTick = now
            writeStatus(temp: nil, pressure: pressure, fans: (try? m.fans()) ?? [])
            reschedule()
            return
        }
        lastTick = now
        var fans: [Fan] = []
        do {
            fans = try m.fans()
            var want: [Int: Double] = [:]
            // A raw reading at `high` must hold for two readings in a row
            // before it means full speed: one core's burst is not a fire.
            hotStreak = (raw ?? 0) >= settings.high ? hotStreak + 1 : 0
            for f in fans where f.controllable {
                guard let rpm = Curve.target(settings, temp: temp, raw: hotStreak >= 2 ? raw : nil, pressure: pressure, engaged: engaged, fan: f, previous: targets[f.id]) else {
                    targets[f.id] = nil
                    continue
                }
                // Only add air: a fan we don't hold is taken only for more
                // than macOS runs it at now. One macOS took back from us is
                // taken again (and counted) below.
                if targets[f.id] == nil, settings.mode.follows, rpm <= f.current + Curve.deadband { continue }
                want[f.id] = rpm
            }
            if want.isEmpty {
                if engaged { releaseAll("") }
            } else {
                for f in fans {
                    guard let rpm = want[f.id] else {
                        // Not ours this tick: forget it, so status and the
                        // next take see it as macOS's.
                        targets[f.id] = nil
                        continue
                    }
                    if !f.manual {
                        // macOS took it back from us, or the first take.
                        if targets[f.id] != nil { reverts += 1 }
                        try m.takeControl(f.id)
                        try m.setTarget(f.id, rpm: rpm)
                        targets[f.id] = rpm
                    } else if let held = targets[f.id], abs(held - rpm) < Curve.deadband, rpm != f.max {
                        continue
                    } else {
                        try m.setTarget(f.id, rpm: rpm)
                        targets[f.id] = rpm
                    }
                }
                engaged = true
                lastError = ""
            }
            failures = 0
        } catch {
            releaseAll("\(error)")
            // A Mac whose firmware keeps refusing: stop trying for a while
            // rather than toggling Ftst every tick, and say so in the status.
            failures += 1
            if failures >= 3 {
                backoffUntil = now.addingTimeInterval(Daemon.backoff)
                lastError = "fan control failed \(failures) times, retrying in \(Int(Daemon.backoff / 60)) min: \(error)"
            }
        }
        writeStatus(temp: temp, pressure: pressure, fans: fans)
        reschedule()
    }

    /// Poll fast only while it matters; an event (a mode change, thermal
    /// pressure) ticks at once whatever the interval.
    func reschedule() {
        let near = (prompt.value ?? 0) >= settings.low - 10
        let next = (engaged || near || settings.mode == .max) ? Daemon.busyInterval : Daemon.idleInterval
        guard next != interval else { return }
        interval = next
        timer.schedule(deadline: .now() + next, repeating: next, leeway: .milliseconds(500))
    }

    /// The menu's view: one KEY<TAB>VALUE… line each, replaced atomically.
    /// soc holds the smoothed temperature the curve uses, then the raw one.
    func writeStatus(temp: Double?, pressure: Int?, fans: [Fan]) {
        let s = settings
        var lines = [
            "updated\t\(Int(Date().timeIntervalSince1970))\t\(Int(interval))",
            "mode\t\(s.mode.rawValue)\t\(Int(s.low))\t\(Int(s.high))",
            "soc\t\(temp.map { String(format: "%.1f", $0) } ?? "-")\t\(raw.map { String(format: "%.1f", $0) } ?? "-")",
            "pressure\t\(pressure.map(String.init) ?? "-")",
            "input\t\(usingPrompt ? "prompt" : "sustained")",
            "control\t\(engaged ? "tuidev" : "macos")\t\(reverts)",
        ]
        for f in fans {
            lines.append("fan\t\(f.id)\t\(whole(f.actual))\t\(whole(targets[f.id] ?? f.target))\t\(whole(f.min))\t\(whole(f.max))\t\(f.manual || targets[f.id] != nil ? "manual" : "auto")")
        }
        if !lastError.isEmpty { lines.append("error\t\(lastError.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " "))") }
        let file = dir.appendingPathComponent("status")
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        chmod(file.path, 0o644)
    }

    /// Re-read the settings and tick when `mode` or `fan.conf` changes, so a
    /// menu click applies at once. Written in place they report .write;
    /// replaced (an editor's save) .delete or .rename, and are watched anew.
    func watch(_ name: String) {
        watchers[name]?.cancel()
        let path = dir.appendingPathComponent(name).path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // Not there (yet): look again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in watch(name) }
            return
        }
        // Back (or new): what it holds now counts, before any change.
        settingsChanged()
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { [self] in
            let ev = src.data
            if ev.contains(.delete) || ev.contains(.rename) { watch(name) } else { settingsChanged() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers[name] = src
    }

    /// Re-read the settings 200 ms after the last change: `printf > mode`
    /// truncates before it writes, and an empty file must never count.
    var pendingReload: DispatchWorkItem?
    func settingsChanged() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [self] in
            settings = Settings.load(from: dir)
            tick()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Tick the moment the kernel's thermal pressure changes.
    func watchPressure() {
        notify_register_dispatch(Machine.pressureName, &pressureToken, .main) { [self] _ in tick() }
    }

    /// Release before the system sleeps: a sleeping Mac must never wake with
    /// fans held by a daemon that hasn't ticked yet. On wake, start over.
    // iokit_common_msg(0x270), (0x280), (0x300): Swift can't import those macros.
    static let canSystemSleep: UInt32 = 0xe000_0270
    static let systemWillSleep: UInt32 = 0xe000_0280
    static let systemHasPoweredOn: UInt32 = 0xe000_0300

    func watchSleep() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(ctx, &powerPort, { ctx, _, type, arg in
            guard let ctx else { return }
            let d = Unmanaged<Daemon>.fromOpaque(ctx).takeUnretainedValue()
            switch type {
            case Daemon.canSystemSleep:
                IOAllowPowerChange(d.rootPort, Int(bitPattern: arg))
            case Daemon.systemWillSleep:
                d.releaseAll("")
                d.sustained = Smoother.sustained()
                d.prompt = Smoother.prompt()
                d.lastTick = nil
                IOAllowPowerChange(d.rootPort, Int(bitPattern: arg))
            case Daemon.systemHasPoweredOn:
                d.tick()
            default: break
            }
        }, &powerNotifier)
        if let powerPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(powerPort).takeUnretainedValue(), .defaultMode)
        }
    }

    func run() -> Never {
        releaseAll("")
        // On the main queue, after any tick in progress: no SMC call from two
        // threads, and launchd's exit timeout (60 s, the plist's) is far off (a tick takes
        // milliseconds; taking a fan, a few seconds at worst).
        onExitSignal(queue: .main) { [self] in
            releaseAll("")
            writeStatus(temp: smoothed, pressure: m.thermalPressure(), fans: (try? m.fans()) ?? [])
        }
        watchSleep()
        watchPressure()
        watch("mode")
        watch("fan.conf")
        timer.setEventHandler { [self] in tick() }
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        timer.resume()
        tick()
        RunLoop.main.run()
        fail("run loop ended")
    }
}

// MARK: - Install

/// Where the daemon lives. The binary and its plist are root's, so nothing a
/// user can write ever runs as root; `mode` and `fan.conf` are root:admin
/// 0664, so an admin (the menu, `agents cool`) changes the mode without a
/// password, and the daemon clamps whatever they hold (Settings.load).
enum Paths {
    static let label = "dev.tuidev.fan"
    static let binary = "/Library/PrivilegedHelperTools/dev.tuidev.fan"
    static let plist = "/Library/LaunchDaemons/dev.tuidev.fan.plist"
    static let dir = "/Library/Application Support/tuidev/fan"
    static let adminGroup: gid_t = 80
}

@discardableResult
func launchctl(_ args: String...) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

/// Write `data` to `path` as owner:group with `perms`, through a temporary
/// file renamed into place (never following a link someone left there).
func place(_ data: Data, at path: String, owner: uid_t = 0, group: gid_t = 0, perms: mode_t) throws {
    let tmp = path + ".new"
    unlink(tmp)
    guard FileManager.default.createFile(atPath: tmp, contents: data) else { throw SMCError.unavailable("can't write \(tmp)") }
    guard chown(tmp, owner, group) == 0, chmod(tmp, perms) == 0, rename(tmp, path) == 0 else {
        unlink(tmp)
        throw SMCError.unavailable("can't place \(path): \(String(cString: strerror(errno)))")
    }
}

/// A settings file, created once and then left as it is (yours to edit).
/// The fan.conf earlier versions seeded, with its defaults written out: such
/// a file is replaced, so it doesn't pin today's defaults to old ones.
let oldSeeds = [
    """
    # tuidev fan curve (read every 2 s by the dev.tuidev.fan daemon).
    # Below low °C the fans are macOS's; from low to high the daemon raises
    # them from their minimum to their maximum. Hottest CPU/GPU core counts.
    # low: 40-90, high: low+5 to 105. Anything else falls back to these.
    low=60
    high=95

    """,
    """
    # tuidev fan curve (the dev.tuidev.fan daemon re-reads it on save).
    # Below low °C the fans are macOS's; from low to high the daemon raises
    # them from their minimum to their maximum. Hottest CPU/GPU core counts.
    # low: 40-75, high: low+5 to 105. Anything else falls back to these.
    low=60
    high=95

    """,
]

func seed(_ name: String, _ text: String) throws {
    let path = Paths.dir + "/" + name
    var st = stat()
    if lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG,
       !oldSeeds.contains((try? String(contentsOfFile: path, encoding: .utf8)) ?? "") {
        // Already there: only make sure of its owner and mode.
        guard chown(path, 0, Paths.adminGroup) == 0, chmod(path, 0o664) == 0 else {
            throw SMCError.unavailable("can't set the owner of \(path)")
        }
        return
    }
    unlink(path)
    try place(Data(text.utf8), at: path, group: Paths.adminGroup, perms: 0o664)
}

/// Each existing component of `path` must be a real directory owned by root
/// that only root can write (or a sticky one, like /tmp), or a root process
/// chowning and removing inside it could be led astray by a swapped link.
func checkRootPath(_ path: String) throws {
    var prefix = ""
    for part in path.split(separator: "/") {
        prefix += "/" + part
        var st = stat()
        if lstat(prefix, &st) != 0 { return }   // the rest is ours to create
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let onlyRoot = (st.st_mode & 0o022) == 0 || (st.st_mode & S_ISVTX) != 0
        guard isDir, st.st_uid == 0, onlyRoot else {
            throw SMCError.unavailable("\(prefix) is not a root-owned directory; refusing to install there")
        }
    }
}

func install(_ m: Machine) throws {
    requireRoot()
    guard m.fanCount > 0 else {
        print("this Mac has no fans: nothing to install")
        exit(3)
    }
    for dir in ["/Library/PrivilegedHelperTools", "/Library/LaunchDaemons", Paths.dir] { try checkRootPath(dir) }
    let fm = FileManager.default
    guard let me = Bundle.main.executablePath else { fail("can't find this binary's own path") }
    let plist: [String: Any] = [
        "Label": Paths.label,
        "ProgramArguments": [Paths.binary, "daemon"],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ProcessType": "Standard",
        "StandardErrorPath": "/var/log/tuidev-fan.log",
        // Time to finish a fan takeover and release on a stop signal.
        "ExitTimeOut": 60,
    ]
    // Stop the running daemon first: it hands the fans back as it exits. The
    // bytes copied below are this running binary's file, the one sudo was
    // asked to run.
    launchctl("bootout", "system/\(Paths.label)")
    try fm.createDirectory(atPath: "/Library/PrivilegedHelperTools", withIntermediateDirectories: true)
    try place(try Data(contentsOf: URL(fileURLWithPath: me)), at: Paths.binary, perms: 0o755)
    try fm.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    guard chown(Paths.dir, 0, 0) == 0, chmod(Paths.dir, 0o755) == 0 else { fail("can't set the owner of \(Paths.dir)") }
    try seed("mode", "auto\n")
    try seed("fan.conf", """
        # tuidev fan curve (the dev.tuidev.fan daemon re-reads it on save).
        # Below low °C the fans are macOS's; from low to high the daemon raises
        # them from their minimum to their maximum, following the hottest
        # CPU/GPU core averaged over minutes (what the palm rest feels).
        # The defaults are shown; uncomment to change them.
        # low: 40-75, high: low+5 to 105. Anything else falls back to these.
        # low=60
        # high=95

        """)
    try place(try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), at: Paths.plist, perms: 0o644)
    launchctl("enable", "system/\(Paths.label)")
    guard launchctl("bootstrap", "system", Paths.plist) == 0 else { fail("launchctl bootstrap failed (see /var/log/tuidev-fan.log)") }
    print("installed: \(Paths.binary) runs as the \(Paths.label) LaunchDaemon (mode: \((try? String(contentsOfFile: Paths.dir + "/mode", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "auto"))")
}

func uninstall(_ m: Machine?) throws {
    requireRoot()
    launchctl("bootout", "system/\(Paths.label)")
    try? m?.release()
    for path in [Paths.plist, Paths.binary] { unlink(path) }
    try checkRootPath(Paths.dir)
    try? FileManager.default.removeItem(atPath: Paths.dir)
    rmdir("/Library/Application Support/tuidev")
    print("uninstalled: the fans are macOS's again")
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

// The curve alone, on numbers: no SMC, so it runs anywhere.
if args.first == "curve" {
    let n = args.dropFirst().map { Double($0) }
    guard n.count >= 1, let temp = n[0], temp.isFinite else { fail("usage: tuidev-fan curve TEMP [PRESSURE] [MODE LOW HIGH MIN MAX PREVIOUS]", code: 2) }
    var s = Settings()
    if args.count > 3, let mode = Settings.Mode(rawValue: args[3]) {
        s.mode = mode
        if let p = mode.preset { (s.low, s.high) = p }
    }
    if n.count > 4, let low = n[3], let high = n[4] { s.low = low; s.high = high }
    let fan = Fan(id: 0, actual: 0, target: 0, min: (n.count > 5 ? n[5] : nil) ?? 1350, max: (n.count > 6 ? n[6] : nil) ?? 5777, manual: false)
    let previous = n.count > 7 ? n[7] : nil
    let pressure = n.count > 1 ? n[1].flatMap { $0.isFinite ? Int($0) : nil } : nil
    let rpm = Curve.target(s, temp: temp, pressure: pressure, engaged: previous != nil, fan: fan, previous: previous)
    print(rpm.map { String(Int($0)) } ?? "macos")
    exit(0)
}

// Uninstall must work even where the SMC can't be opened (a VM, a new macOS).
if args.first == "uninstall" {
    do { try uninstall(try? Machine()) } catch { fail("\(error)") }
    exit(0)
}

let machine: Machine
do { machine = try Machine() } catch { fail("\(error)") }

do {
    switch args.first ?? "status" {
    case "status":
        try status(machine, tsv: args.contains("--tsv"))
    case "try":
        let rpm = args.count > 1 ? Double(args[1]) : nil
        let secs = args.count > 2 ? Int(args[2]) ?? 30 : 30
        guard (args.count < 2 || rpm != nil), (5...600).contains(secs) else { fail("usage: tuidev-fan try [RPM] [SECONDS 5-600]", code: 2) }
        try tryHold(machine, rpm: rpm, seconds: secs)
    case "release":
        requireRoot()
        try machine.release()
        print("fans released to macOS")
    case "install":
        try install(machine)
    case "daemon":
        requireRoot()
        Daemon(machine, dir: URL(fileURLWithPath: Paths.dir, isDirectory: true)).run()
    case "-h", "--help", "help":
        print("usage: tuidev-fan status [--tsv] | try [RPM] [SECONDS] | release | install | uninstall | daemon")
    default:
        fail("unknown command '\(args[0])' (try --help)", code: 2)
    }
} catch {
    if geteuid() == 0 { try? machine.release() }
    fail("\(error)")
}
