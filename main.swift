import AppKit
import AVFoundation
import ServiceManagement

// MARK: - Voices
//
// Every click is synthesized: optional noise "ticks", a bank of decaying resonators
// (the body that rings), and an optional pitch-swept sine for the "liquid" voices.

struct Burst { let ms: Double; let amp: Double; let lenMs: Double; let bright: Double }
struct Mode { let f: Double; let tau: Double; let amp: Double }
struct Sweep { let from: Double; let to: Double; let ms: Double; let tau: Double; let amp: Double }

struct Voice {
    let id: String
    let name: String
    var bursts: [Burst] = []
    var modes: [Mode] = []
    var sweep: Sweep? = nil
    var tick = 0.2
    var level = 1.0
}

let voices: [Voice] = [
    Voice(id: "dial", name: "Dial (knob detent)",
          bursts: [Burst(ms: 0, amp: 1, lenMs: 0.5, bright: 0.8)],
          modes: [Mode(f: 1900, tau: 0.004, amp: 0.6), Mode(f: 950, tau: 0.008, amp: 0.8),
                  Mode(f: 320, tau: 0.012, amp: 0.6)], tick: 0.4),
    Voice(id: "liquid", name: "Liquid drop",
          bursts: [Burst(ms: 0, amp: 0.3, lenMs: 0.4, bright: 0.5)],
          modes: [Mode(f: 420, tau: 0.010, amp: 0.3)],
          sweep: Sweep(from: 1100, to: 380, ms: 18, tau: 0.018, amp: 1), tick: 0.05),
    Voice(id: "deep", name: "Deep thump",
          bursts: [Burst(ms: 0, amp: 1, lenMs: 1.4, bright: 0.3)],
          modes: [Mode(f: 620, tau: 0.008, amp: 0.4), Mode(f: 150, tau: 0.022, amp: 1)],
          sweep: Sweep(from: 260, to: 140, ms: 12, tau: 0.02, amp: 0.5), tick: 0.08),
    Voice(id: "wood", name: "Wood block",
          bursts: [Burst(ms: 0, amp: 1, lenMs: 0.6, bright: 0.7)],
          modes: [Mode(f: 720, tau: 0.012, amp: 0.9), Mode(f: 1950, tau: 0.007, amp: 0.5),
                  Mode(f: 3350, tau: 0.004, amp: 0.3)], tick: 0.2),
    Voice(id: "glass", name: "Glass tick",
          bursts: [Burst(ms: 0, amp: 1, lenMs: 0.3, bright: 1)],
          modes: [Mode(f: 2600, tau: 0.03, amp: 0.6), Mode(f: 5400, tau: 0.02, amp: 0.3)],
          tick: 0.3, level: 0.7),
    Voice(id: "ratchet", name: "Ratchet",
          bursts: [Burst(ms: 0, amp: 1, lenMs: 0.3, bright: 1), Burst(ms: 3, amp: 0.6, lenMs: 0.3, bright: 1)],
          modes: [Mode(f: 3800, tau: 0.003, amp: 0.8), Mode(f: 1400, tau: 0.005, amp: 0.4)], tick: 0.9),
    Voice(id: "bubble", name: "Bubble",
          sweep: Sweep(from: 320, to: 820, ms: 22, tau: 0.02, amp: 1), tick: 0, level: 0.8),
]

// MARK: - Synthesis

final class ClickBank {
    let format: AVAudioFormat
    private(set) var down: [AVAudioPCMBuffer] = []  // scrolling down
    private(set) var up: [AVAudioPCMBuffer] = []    // scrolling up: a touch higher
    private let sr: Double = 44100

    init() { format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)! }

    func build(_ v: Voice) {
        down = (0..<6).map { _ in render(v, pitch: .random(in: 0.97...1.03)) }
        up = (0..<6).map { _ in render(v, pitch: .random(in: 1.09...1.15)) }
    }

    private func render(_ v: Voice, pitch: Double) -> AVAudioPCMBuffer {
        let maxTau = max(v.modes.map(\.tau).max() ?? 0, v.sweep?.tau ?? 0)
        let n = Int(min(0.2, 5 * maxTau + 0.01) * sr)
        var exc = [Double](repeating: 0, count: n)
        var out = [Double](repeating: 0, count: n)

        for b in v.bursts {
            let start = Int(b.ms / 1000 * sr)
            let len = max(1.0, b.lenMs / 1000 * sr)
            let a = 0.05 + 0.9 * b.bright
            var lp = 0.0, prev = 0.0
            for i in 0..<Int(len * 5) where start + i < n {
                let w = Double.random(in: -1...1)
                lp += (w - lp) * a
                let hp = w - prev; prev = w
                exc[start + i] += b.amp * exp(-Double(i) / len) * (b.bright * hp + (1 - b.bright) * lp)
                out[start + i] += v.tick * b.amp * hp * exp(-Double(i) / (0.0006 * sr))
            }
        }

        for m in v.modes {
            let f = m.f * pitch
            guard f < sr * 0.45 else { continue }
            let r = exp(-1 / (m.tau * sr))
            let w = 2 * .pi * f / sr
            let c1 = 2 * r * cos(w), c2 = -r * r
            let g = m.amp * (1 - r) * 2 * sin(w) * 8
            var y1 = 0.0, y2 = 0.0
            for i in 0..<n {
                let y = exc[i] + c1 * y1 + c2 * y2
                y2 = y1; y1 = y
                out[i] += g * y
            }
        }

        if let s = v.sweep {
            var phase = 0.0
            let sweepN = s.ms / 1000 * sr
            for i in 0..<n {
                let k = min(1, Double(i) / sweepN)
                let f = (s.from + (s.to - s.from) * (1 - pow(1 - k, 2))) * pitch  // fast then settle
                phase += 2 * .pi * f / sr
                let t = Double(i) / sr
                out[i] += s.amp * sin(phase) * exp(-t / s.tau) * min(1, t / 0.0005)
            }
        }

        let peak = out.map(abs).max() ?? 1
        let scale = peak > 0 ? 0.8 * v.level / peak : 0
        let fade = Int(0.004 * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let l = buf.floatChannelData![0], rc = buf.floatChannelData![1]
        for i in 0..<n {
            var x = out[i] * scale
            if i > n - fade { x *= Double(n - i) / Double(fade) }
            l[i] = Float(x); rc[i] = Float(x)
        }
        return buf
    }
}

// MARK: - Audio player

final class Player {
    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var next = 0
    let bank = ClickBank()

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    init(voice: Voice) {
        bank.build(voice)
        for _ in 0..<12 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: bank.format)
            nodes.append(n)
        }
        start()
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.start() }
    }

    private func start() {
        if !engine.isRunning { try? engine.start() }
    }

    func play(_ buf: AVAudioPCMBuffer?, gain: Float = 1) {
        guard let buf else { return }
        start()
        let n = nodes[next]
        next = (next + 1) % nodes.count
        n.stop()
        n.volume = gain
        n.scheduleBuffer(buf, at: nil, options: [])
        n.play()
    }
}

// MARK: - Scroll → detents

enum Spacing: String, CaseIterable {
    case fine = "Fine", normal = "Normal", coarse = "Coarse"
    var points: Double { switch self { case .fine: 22; case .normal: 40; case .coarse: 70 } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var player: Player!
    private var monitor: Any?

    private var enabled = true
    private var haptics = true
    private var momentum = true
    private var spacing = Spacing.normal
    private var voice = voices[0]

    private var travelled = 0.0          // scroll distance since the last detent
    private var lastClick = Date.distantPast
    private var volumeLabel: NSMenuItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        momentum = defaults.object(forKey: "momentum") as? Bool ?? true
        spacing = Spacing(rawValue: defaults.string(forKey: "spacing") ?? "") ?? .normal
        voice = voices.first { $0.id == defaults.string(forKey: "voice") } ?? voices[0]
        player = Player(voice: voice)
        player.volume = defaults.object(forKey: "volume") as? Float ?? 0.5

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.handle(e)
        }
    }

    private func handle(_ e: NSEvent) {
        guard enabled else { return }
        let isMomentum = !e.momentumPhase.isEmpty
        if isMomentum && !momentum { return }
        if e.phase == .began { travelled = 0 }

        // mouse wheels send one event per notch; trackpads send many small pixel deltas
        let dy = e.scrollingDeltaY, dx = e.scrollingDeltaX
        let delta = abs(dy) >= abs(dx) ? dy : dx
        guard delta != 0 else { return }
        let dist = e.hasPreciseScrollingDeltas ? abs(delta) : spacing.points
        travelled += dist
        guard travelled >= spacing.points else { return }
        travelled = travelled.truncatingRemainder(dividingBy: spacing.points)

        // at high speed, space clicks out and soften them so a fling becomes a smooth blur
        let now = Date()
        let dt = now.timeIntervalSince(lastClick)
        if dt < 0.018 { return }
        lastClick = now
        let gain = Float(max(0.45, min(1, (dt - 0.018) / 0.06 + 0.45)))

        player.play((delta > 0 ? player.bank.up : player.bank.down).randomElement(), gain: gain)
        if haptics && !isMomentum {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: Menu

    private func rebuildMenu() {
        statusItem.button?.image = NSImage(
            systemSymbolName: enabled ? "dial.medium.fill" : "dial.medium",
            accessibilityDescription: "ScrollClick")

        let m = NSMenu()
        let on = item("Clicks On", #selector(toggleEnabled))
        on.state = enabled ? .on : .off
        m.addItem(on)
        m.addItem(.separator())

        let voiceItem = NSMenuItem(title: "Sound: \(voice.name)", action: nil, keyEquivalent: "")
        let vs = NSMenu()
        for v in voices {
            let it = item(v.name, #selector(pickVoice(_:)))
            it.representedObject = v.id
            it.state = v.id == voice.id ? .on : .off
            vs.addItem(it)
        }
        voiceItem.submenu = vs
        m.addItem(voiceItem)

        let spItem = NSMenuItem(title: "Click spacing: \(spacing.rawValue)", action: nil, keyEquivalent: "")
        let ss = NSMenu()
        for s in Spacing.allCases {
            let it = item(s.rawValue, #selector(pickSpacing(_:)))
            it.representedObject = s.rawValue
            it.state = s == spacing ? .on : .off
            ss.addItem(it)
        }
        spItem.submenu = ss
        m.addItem(spItem)
        m.addItem(.separator())

        let vl = NSMenuItem(title: volumeTitle, action: nil, keyEquivalent: "")
        vl.isEnabled = false
        volumeLabel = vl
        m.addItem(vl)
        let slider = NSSlider(value: Double(player.volume), minValue: 0, maxValue: 1,
                              target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 18, y: 4, width: 190, height: 22)
        let wrap = NSView(frame: NSRect(x: 0, y: 0, width: 226, height: 30))
        wrap.addSubview(slider)
        let si = NSMenuItem()
        si.view = wrap
        m.addItem(si)
        m.addItem(.separator())

        let h = item("Trackpad haptics", #selector(toggleHaptics))
        h.state = haptics ? .on : .off
        m.addItem(h)
        let mo = item("Click during momentum scroll", #selector(toggleMomentum))
        mo.state = momentum ? .on : .off
        m.addItem(mo)
        m.addItem(.separator())

        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        m.addItem(item("Quit ScrollClick", #selector(quit), key: "q"))
        statusItem.menu = m
    }

    private var volumeTitle: String { "Volume: \(Int((player.volume * 100).rounded()))%" }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        return it
    }

    private func flip(_ v: inout Bool, _ key: String) {
        v.toggle()
        defaults.set(v, forKey: key)
        rebuildMenu()
    }

    @objc private func toggleEnabled() { flip(&enabled, "enabled") }
    @objc private func toggleHaptics() { flip(&haptics, "haptics") }
    @objc private func toggleMomentum() { flip(&momentum, "momentum") }

    @objc private func pickVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let v = voices.first(where: { $0.id == id }) else { return }
        voice = v
        defaults.set(id, forKey: "voice")
        player.bank.build(v)
        // preview: three detents
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) { [weak self] in
                self?.player.play(self?.player.bank.down.randomElement())
            }
        }
        rebuildMenu()
    }

    @objc private func pickSpacing(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = Spacing(rawValue: raw) else { return }
        spacing = s
        defaults.set(raw, forKey: "spacing")
        rebuildMenu()
    }

    @objc private func volumeChanged(_ s: NSSlider) {
        player.volume = s.floatValue
        defaults.set(player.volume, forKey: "volume")
        volumeLabel?.title = volumeTitle
        if NSApp.currentEvent?.type == .leftMouseUp {
            player.play(player.bank.down.randomElement())
        }
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            NSSound.beep()
        }
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
