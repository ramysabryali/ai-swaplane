import AVFoundation
import AppKit
import SwiftUI

/// Appearance override (docs/DESIGN.md): follows the system unless the user picks one.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Account colours the user can pick (stored by name in `AccountGroup.colorName`).
enum Palette {
    static let names = ["blue", "green", "purple", "orange", "pink", "teal", "red", "yellow"]
    static func ns(_ name: String) -> NSColor {
        switch name {
        case "green": NSColor(srgbRed: 0.435, green: 0.812, blue: 0.592, alpha: 1)
        case "purple": NSColor(srgbRed: 0.780, green: 0.573, blue: 0.918, alpha: 1)
        case "orange": NSColor(srgbRed: 0.949, green: 0.651, blue: 0.353, alpha: 1)
        case "pink": NSColor(srgbRed: 0.898, green: 0.561, blue: 0.690, alpha: 1)
        case "teal": NSColor(srgbRed: 0.435, green: 0.816, blue: 0.784, alpha: 1)
        case "red": NSColor(srgbRed: 0.941, green: 0.380, blue: 0.373, alpha: 1)
        case "yellow": NSColor(srgbRed: 0.949, green: 0.757, blue: 0.306, alpha: 1)
        default: NSColor(srgbRed: 0.357, green: 0.553, blue: 0.937, alpha: 1)
        }
    }
    static func color(_ name: String) -> Color { Color(nsColor: ns(name)) }
}

/// Brand tokens. The signal colour is a single value (orange `#FF8A3D`).
enum Theme {
    static let signalNS = NSColor(srgbRed: 1.0, green: 0.541, blue: 0.239, alpha: 1)
    static let signal = Color(nsColor: signalNS)

    private static func dyn(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) {
            $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    static let panel = dyn(dark: rgb(0x121B2B), light: rgb(0xF7F9FC))
    static let fg = dyn(dark: rgb(0xE8EEF7), light: rgb(0x0B1220))
    static let muted = dyn(dark: rgb(0x8FA0BA), light: rgb(0x5B6B82))
    static let card = dyn(dark: NSColor.white.withAlphaComponent(0.06), light: rgb(0x0B1220, 0.05))
    static let hover = dyn(dark: NSColor.white.withAlphaComponent(0.07), light: rgb(0x0B1220, 0.06))
    static let line = dyn(dark: NSColor.white.withAlphaComponent(0.12), light: rgb(0x0B1220, 0.14))
    static let track = dyn(dark: rgb(0x2A3A55), light: rgb(0xD5DDE9))
    static let ink = Color(nsColor: rgb(0x0B1220))
    static let warn = Color(nsColor: rgb(0xF2C14E))
    static let danger = Color(nsColor: rgb(0xF0615F))
    static let success = Color(nsColor: rgb(0x6FCF97))

    /// Account colour normally; amber from 80 %, red from 95 %.
    static func limitColor(_ percent: Double, base: Color) -> Color {
        percent >= 95 ? danger : percent >= 80 ? warn : base
    }
    static func limitNS(_ percent: Double, base: NSColor) -> NSColor {
        percent >= 95 ? rgb(0xF0615F) : percent >= 80 ? rgb(0xF2C14E) : base
    }
}

// MARK: Sound

/// Quiet synthesised cues (no audio assets). Disabled by the Sound setting.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    enum Cue { case tick, select, on, off, success, ping, remove, warn }

    var enabled: Bool { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let rate = 44_100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    private var prepared = false

    private struct Tone { var f: Double; var at: Double; var dur: Double; var vol: Float; var to: Double? = nil }

    func play(_ cue: Cue) {
        guard enabled else { return }
        let tones: [Tone]
        switch cue {
        case .tick: tones = [Tone(f: 1250, at: 0, dur: 0.05, vol: 0.05)]
        case .select: tones = [Tone(f: 620, at: 0, dur: 0.08, vol: 0.06, to: 760)]
        case .on: tones = [Tone(f: 784, at: 0, dur: 0.09, vol: 0.06), Tone(f: 1175, at: 0.07, dur: 0.14, vol: 0.06)]
        case .off: tones = [Tone(f: 700, at: 0, dur: 0.12, vol: 0.05, to: 480)]
        case .success:
            tones = [Tone(f: 523, at: 0, dur: 0.16, vol: 0.06), Tone(f: 659, at: 0.09, dur: 0.16, vol: 0.06),
                     Tone(f: 988, at: 0.18, dur: 0.34, vol: 0.06)]
        case .ping: tones = [Tone(f: 1318, at: 0, dur: 0.55, vol: 0.07), Tone(f: 1760, at: 0.11, dur: 0.5, vol: 0.035)]
        case .remove: tones = [Tone(f: 460, at: 0, dur: 0.2, vol: 0.06, to: 300)]
        case .warn: tones = [Tone(f: 210, at: 0, dur: 0.22, vol: 0.06)]
        }
        let total = (tones.map { $0.at + $0.dur }.max() ?? 0.1) + 0.05
        let frames = AVAudioFrameCount(total * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }
        for t in tones {
            let start = Int(t.at * rate), n = Int(t.dur * rate)
            var phase = 0.0
            for i in 0..<n where start + i < Int(frames) {
                let x = Double(i) / Double(n)
                let f = t.to.map { t.f * pow($0 / t.f, x) } ?? t.f
                phase += 2 * .pi * f / rate
                let attack = min(1, Double(i) / (0.008 * rate))
                out[start + i] += Float(sin(phase) * attack * exp(-5 * x)) * t.vol
            }
        }
        if !prepared {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            prepared = true
        }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        node.scheduleBuffer(buf, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }
}

// MARK: Menu bar icon (twin bars)

enum MenuBarIcon {
    /// Fork glyph, a dot per tool in the account colour, and two micro bars (session, weekly).
    static func image(
        primary: NSColor?, secondary: NSColor?, session: Double?, weekly: Double?
    ) -> NSImage {
        let img = NSImage(size: NSSize(width: 36, height: 18), flipped: true) { _ in
            let ink = NSColor.labelColor
            let s: CGFloat = 0.8, ox: CGFloat = 0.5
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: y * s) }
            let g = NSBezierPath()
            g.lineWidth = 1.6; g.lineCapStyle = .round
            g.move(to: pt(3, 11)); g.line(to: pt(8, 11))
            g.curve(to: pt(14, 6), controlPoint1: pt(11, 11), controlPoint2: pt(11, 6)); g.line(to: pt(19, 6))
            g.move(to: pt(8, 11))
            g.curve(to: pt(14, 16), controlPoint1: pt(11, 11), controlPoint2: pt(11, 16)); g.line(to: pt(19, 16))
            ink.setStroke(); g.stroke()
            func dot(_ c: NSColor?, _ y: CGFloat) {
                guard let c else { return }
                c.setFill()
                NSBezierPath(ovalIn: NSRect(x: ox + 19 * s - 2.1, y: y * s - 2.1, width: 4.2, height: 4.2)).fill()
            }
            dot(primary, 6); dot(secondary ?? primary, 16)
            func bar(_ v: Double?, y: CGFloat) {
                let r = NSRect(x: 21, y: y, width: 14, height: 3.5)
                ink.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: r, xRadius: 1.75, yRadius: 1.75).fill()
                guard let v, let base = primary else { return }
                Theme.limitNS(v, base: base).setFill()
                let w = max(3.5, r.width * CGFloat(min(100, max(0, v)) / 100))
                NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: w, height: r.height), xRadius: 1.75, yRadius: 1.75).fill()
            }
            bar(session, y: 4.5); bar(weekly, y: 10.5)
            return true
        }
        img.isTemplate = false
        return img
    }
}
