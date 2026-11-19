// FingerStick — hold a modifier key (Control by default) and a pointer-finger stick taps the screen at your cursor.
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Tunables

let stickLen: CGFloat = 300                 // fingertip → end of stick (local units = points)
let baseAngle: CGFloat = 30 * .pi / 180     // stick comes in from the lower right
let liftDeg: CGFloat = 7                    // how far the tip swings off the screen between taps
let anchor = NSPoint(x: 60, y: 330)         // fingertip position inside the overlay window
let viewSize = NSSize(width: 320, height: 380)
let tapPeriod = 0.2                         // seconds per tap (5 taps/s)
let holdDelay = 0.15                        // ignore quick taps / fast shortcuts

/// 0 = touching the screen (impact), 1 = fully lifted. Slow lift, fast strike.
func liftAt(_ p: Double) -> CGFloat {
    p < 0.7 ? CGFloat(sin(p / 0.7 * .pi / 2)) : CGFloat(cos((p - 0.7) / 0.3 * .pi / 2))
}

// MARK: - Sound: synthesized taps (noise click + two damped tones, optional second hit)

struct Synth { let name: String; let hi: Double; let lo: Double; let decay: Double; let echo: Double }
let synths = [
    Synth(name: "Clack (plastic)", hi: 2600, lo: 1150, decay: 1, echo: 0.6),
    Synth(name: "Knock (wood)", hi: 900, lo: 420, decay: 2.2, echo: 0),
    Synth(name: "Tick (click)", hi: 4200, lo: 2000, decay: 0.5, echo: 0),
    Synth(name: "Bonk (hollow)", hi: 600, lo: 220, decay: 3, echo: 0.3),
]

func clackWAV(_ s: Synth = synths[0], rate: Int = 44100) -> Data {
    let n = rate * 70 / 1000
    var seed: UInt32 = 7
    func hit(_ t: Double, _ noise: Double) -> Double {
        guard t >= 0 else { return 0 }
        return noise * exp(-t / (0.0015 * s.decay)) * 0.55
            + sin(2 * .pi * s.hi * t) * exp(-t / (0.008 * s.decay)) * 0.35
            + sin(2 * .pi * s.lo * t) * exp(-t / (0.016 * s.decay)) * 0.25
    }
    var d = Data()
    func u32(_ x: UInt32) { withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ x: UInt16) { withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2))
    d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
    u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
    for i in 0..<n {
        let t = Double(i) / Double(rate)
        seed = seed &* 1664525 &+ 1013904223
        let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
        let v = hit(t, noise) + s.echo * hit(t - 0.022, noise)
        u16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32000)))
    }
    return d
}

// MARK: - Drawing (all in code, fingertip at local origin, finger pointing +y)

final class StickView: NSView {
    var lift: CGFloat = 0 { didSet { needsDisplay = true } }

    private func paint(_ p: NSBezierPath, _ fill: NSColor, _ edge: NSColor = NSColor(white: 0.45, alpha: 1)) {
        fill.setFill(); p.fill()
        edge.setStroke(); p.lineWidth = 1.5; p.stroke()
    }
    private func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.rotate(by: baseAngle)
        // swing about the far end of the stick, like a hand flicking it
        ctx.translateBy(x: 13, y: -stickLen)
        ctx.rotate(by: -lift * liftDeg * .pi / 180)
        ctx.translateBy(x: -13, y: stickLen)

        // Right glove seen from the back: index finger on the thumb-side edge, the other three
        // fingers curled into knuckle bumps stepping down beside it, thumb tucked low on the left.
        let white = NSColor(white: 0.98, alpha: 1)
        let edge = NSColor(white: 0.45, alpha: 1)
        let thumb = rr(-4, -7, 30, 14, 7)
        var tf = AffineTransform(translationByX: -6, byY: -72)
        tf.rotate(byDegrees: 125)
        thumb.transform(using: tf)
        let glove = [
            rr(-8, -50, 16, 52, 8),      // index finger (tip at y≈+2)
            rr(8, -54, 12, 18, 6),       // middle knuckle
            rr(19, -54, 11, 15, 5.5),    // ring knuckle
            rr(29, -56, 9, 12, 4.5),     // pinky knuckle
            rr(-10, -92, 47, 48, 14),    // back of hand
            thumb,
        ]

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowOffset = NSSize(width: 3, height: -4)
        shadow.shadowBlurRadius = 5
        ctx.saveGState()
        shadow.set()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)   // one shadow for the whole silhouette
        paint(rr(9, -stickLen, 8, stickLen - 100, 3), NSColor(red: 0.85, green: 0.70, blue: 0.50, alpha: 1),
              NSColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 1))   // wooden stick
        paint(rr(-5, -112, 36, 24, 7), white)                          // cuff
        // stroke everything, then fill everything → a single merged outline, no seams
        edge.setStroke(); for p in glove { p.lineWidth = 3; p.stroke() }
        white.setFill(); for p in glove { p.fill() }
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        func line(_ a: NSPoint, _ b: NSPoint, _ w: CGFloat, _ c: NSColor) {
            let s = NSBezierPath(); s.move(to: a); s.line(to: b)
            s.lineWidth = w; s.lineCapStyle = .round; c.setStroke(); s.stroke()
        }
        // creases between the fingers
        line(NSPoint(x: 8, y: -38), NSPoint(x: 8.5, y: -49), 1.5, edge)
        line(NSPoint(x: 19.5, y: -41), NSPoint(x: 19.5, y: -49), 1.5, edge)
        line(NSPoint(x: 29.5, y: -46), NSPoint(x: 29.5, y: -51), 1.5, edge)
        // the three glove stitches on the back
        for x: CGFloat in [7, 14, 21] { line(NSPoint(x: x - 1, y: -80), NSPoint(x: x + 1, y: -63), 2.2, .black) }
    }
}

// MARK: - Trigger key

let triggers: [(name: String, flag: NSEvent.ModifierFlags)] = [
    ("Control", .control), ("Option", .option), ("Command", .command), ("Shift", .shift), ("Fn", .function),
]

/// True when `trigger` is the only modifier down. Fn is ignored unless it is the trigger,
/// because arrow and function keys set it on their own.
func isTriggerAlone(_ flags: NSEvent.ModifierFlags, _ trigger: NSEvent.ModifierFlags) -> Bool {
    var f = flags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad])
    if trigger != .function { f.remove(.function) }
    return f == trigger
}

func alert(_ title: String, _ info: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    NSApp.activate(ignoringOtherApps: true)
    a.runModal()
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let view = StickView(frame: NSRect(origin: .zero, size: viewSize))
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: viewSize), styleMask: .borderless,
                       backing: .buffered, defer: false)
    var sounds: [NSSound] = []
    var soundIdx = 0
    let systemDir = "/System/Library/Sounds"
    /// A synth name, a macOS system sound name, or an absolute path to the user's own file.
    var soundName = UserDefaults.standard.string(forKey: "sound") ?? synths[0].name
    var triggerName = UserDefaults.standard.string(forKey: "trigger")
        .flatMap { n in triggers.contains { $0.name == n } ? n : nil } ?? "Control"
    var trigger: NSEvent.ModifierFlags { triggers.first { $0.name == triggerName }?.flag ?? .control }

    let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let soundSub = NSMenu()
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    var status: NSStatusItem?
    var heldSince: Date?
    var tapStart: Date?
    var lastTap = -1
    var taps = 0
    var forceUntil: Date?   // --demo: pretend the trigger key is held

    // MARK: Sound

    /// 3 players per sound so fast taps can overlap instead of going silent.
    func loadSounds() {
        if let s = synths.first(where: { $0.name == soundName }) {
            sounds = (0..<3).compactMap { _ in NSSound(data: clackWAV(s)) }
        } else {
            let path = soundName.hasPrefix("/") ? soundName : "\(systemDir)/\(soundName).aiff"
            sounds = (0..<3).compactMap { _ in NSSound(contentsOfFile: path, byReference: true) }
        }
        if sounds.isEmpty && soundName != synths[0].name { soundName = synths[0].name; loadSounds() }   // file moved or unreadable
    }

    func setSound(_ key: String) {
        soundName = key
        loadSounds()
        UserDefaults.standard.set(soundName, forKey: "sound")   // after loading, so a bad file isn't saved
        rebuildSoundMenu()
        clack()   // preview
    }

    @objc func pickSound(_ item: NSMenuItem) { setSound(item.representedObject as? String ?? item.title) }

    @objc func chooseSoundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a short sound to play on every tap"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setSound(url.path)
        if soundName != url.path {
            alert("FingerStick can't play “\(url.lastPathComponent)”", "Try an AIFF, WAV, MP3 or M4A file.")
        }
    }

    func rebuildSoundMenu() {
        soundSub.removeAllItems()
        func add(_ title: String, _ key: String) {
            let i = NSMenuItem(title: title, action: #selector(pickSound(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = key
            i.state = key == soundName ? .on : .off
            soundSub.addItem(i)
        }
        synths.forEach { add($0.name, $0.name) }
        soundSub.addItem(.separator())
        ((try? FileManager.default.contentsOfDirectory(atPath: systemDir)) ?? [])
            .filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
            .forEach { add($0, $0) }
        soundSub.addItem(.separator())
        if soundName.hasPrefix("/") { add((soundName as NSString).lastPathComponent, soundName) }
        let choose = NSMenuItem(title: "Choose Sound File…", action: #selector(chooseSoundFile), keyEquivalent: "")
        choose.target = self
        soundSub.addItem(choose)
    }

    // MARK: Trigger key

    func triggerMenu() -> NSMenuItem {
        let sub = NSMenu()
        for t in triggers {
            let i = NSMenuItem(title: t.name, action: #selector(pickTrigger(_:)), keyEquivalent: "")
            i.target = self
            i.state = t.name == triggerName ? .on : .off
            sub.addItem(i)
        }
        let root = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        root.submenu = sub
        return root
    }

    @objc func pickTrigger(_ item: NSMenuItem) {
        triggerName = item.title
        UserDefaults.standard.set(triggerName, forKey: "trigger")
        item.menu?.items.forEach { $0.state = $0.title == triggerName ? .on : .off }
        hint.title = "Hold \(triggerName) to tap"
    }

    // MARK: Launch at login

    @objc func toggleLogin() {
        guard #available(macOS 13, *) else { return }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            alert("Couldn't change Launch at Login", error.localizedDescription)
        }
        if svc.status == .requiresApproval {
            alert("Allow FingerStick in Login Items", "Turn FingerStick on in System Settings → General → Login Items.")
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshLogin()
    }

    func refreshLogin() {
        if #available(macOS 13, *) { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshLogin() }   // it can be switched off in System Settings too

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.contentView = view

        loadSounds()
        rebuildSoundMenu()
        hint.title = "Hold \(triggerName) to tap"
        let sound = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        sound.submenu = soundSub
        loginItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(triggerMenu())
        menu.addItem(sound)
        if #available(macOS 13, *) { menu.addItem(loginItem) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FingerStick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "☝️"
        item.menu = menu
        status = item

        // Polling the modifier state needs no Accessibility/Input Monitoring permission.
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
    }

    func clack() {
        taps += 1
        guard !sounds.isEmpty else { return }
        let s = sounds[soundIdx % sounds.count]; soundIdx += 1
        s.stop(); s.play()
    }

    func tick() {
        let now = Date()
        let down = isTriggerAlone(NSEvent.modifierFlags, trigger) || (forceUntil.map { now < $0 } ?? false)
        if !down { heldSince = nil } else if heldSince == nil { heldSince = now }
        let held = heldSince.map { now.timeIntervalSince($0) >= holdDelay } ?? false

        guard held else {
            if tapStart != nil { win.orderOut(nil); tapStart = nil }
            return
        }
        let m = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: m.x - anchor.x, y: m.y - anchor.y))
        if tapStart == nil { tapStart = now; lastTap = -1; win.orderFrontRegardless() }
        let e = now.timeIntervalSince(tapStart!) / tapPeriod
        let k = Int(e)
        if k != lastTap { lastTap = k; clack() }   // sound exactly on the impact frame
        view.lift = liftAt(e - Double(k))
    }
}

// MARK: - Self-check: `FingerStick --selftest <outdir>` renders PNGs and asserts basics

@discardableResult
func renderPNG(_ v: NSView, _ path: String) -> NSBitmapImageRep {
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    return rep
}

func selfTest(_ dir: String) -> Int32 {
    let wav = clackWAV()
    precondition(wav.count == 44 + 44100 * 70 / 1000 * 2, "wav size")
    precondition(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF", "wav header")
    for s in synths { precondition(NSSound(data: clackWAV(s)) != nil, "NSSound can't decode \(s.name)") }
    precondition(isTriggerAlone(.control, .control) && !isTriggerAlone([.control, .shift], .control), "trigger alone")
    precondition(isTriggerAlone([.control, .function], .control), "arrow keys (Fn flag) keep Control held")
    precondition(isTriggerAlone(.function, .function) && !isTriggerAlone(.function, .control), "Fn trigger")
    precondition(isTriggerAlone([.option, .capsLock], .option), "Caps Lock ignored")
    precondition(liftAt(0) == 0 && abs(liftAt(0.7) - 1) < 1e-9 && abs(liftAt(0.9999)) < 1e-3, "lift curve")

    let v = StickView(frame: NSRect(origin: .zero, size: viewSize))
    for (name, lift) in [("impact", CGFloat(0)), ("lifted", CGFloat(1))] {
        v.lift = lift
        let rep = renderPNG(v, "\(dir)/\(name).png")
        let sc = CGFloat(rep.pixelsWide) / viewSize.width
        // bitmap y runs top-down; probe 2pt inside the fingertip, along the finger
        let px = Int((anchor.x + 2 * -sin(baseAngle)) * sc)
        let py = Int((viewSize.height - anchor.y + 2 * cos(baseAngle)) * sc)
        let a = rep.colorAt(x: px, y: py)?.alphaComponent ?? 0
        print("\(name): alpha at fingertip = \(a)")
        if lift == 0 { precondition(a > 0.9, "fingertip not on the anchor at impact") }
        else { precondition(a < 0.1, "fingertip should leave the anchor when lifted") }
    }
    print("selftest OK")
    return 0
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest") {
    exit(selfTest(i + 1 < args.count ? args[i + 1] : "."))
}
if let i = args.firstIndex(of: "--frames") {   // one tap cycle as PNGs, for the README GIF
    let dir = i + 1 < args.count ? args[i + 1] : "."
    let v = StickView(frame: NSRect(origin: .zero, size: viewSize))
    for f in 0..<12 {
        v.lift = liftAt(Double(f) / 12)
        renderPNG(v, "\(dir)/frame\(String(format: "%02d", f)).png")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
if args.contains("--demo") {
    delegate.forceUntil = Date().addingTimeInterval(2 + holdDelay)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        print("demo taps: \(delegate.taps) (expected ~\(Int(2 / tapPeriod))), window hidden: \(!delegate.win.isVisible), sound: \(delegate.soundName), menu: \(delegate.hint.title)")
        exit(0)
    }
}
app.run()
