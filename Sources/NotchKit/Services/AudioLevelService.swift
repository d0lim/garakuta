import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// Band levels of whatever the Mac is playing, so the now-playing bars can move with the music.
///
/// The samples come from a CoreAudio process tap, a stereo mixdown of every app's output. They are turned into
/// a handful of band levels and discarded; nothing is recorded, written anywhere or sent anywhere. The tap only
/// exists while something is playing and the bars are on screen, and it leaves the output device alone: the
/// aggregate device that carries it has no sub-devices, so playback is not routed through anything of ours.
@MainActor
@Observable
public final class AudioLevelService {
    public static let bandCount = 5

    /// One level per band, 0...1, low frequencies first. All zero while nothing is being tapped.
    ///
    /// Deliberately not observed: a SwiftUI update a dozen times a second costs several times more than the tap
    /// and the analysis together, because the bars sit in a row that measures itself. Whatever draws them
    /// subscribes instead and hands the numbers straight to its layers.
    @ObservationIgnored public private(set) var levels = [Float](repeating: 0, count: AudioLevelService.bandCount)
    /// True while the tap is alive and delivering samples.
    public private(set) var isRunning = false

    /// Turned on by the panel when the setting is enabled and something is playing.
    public var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    private var subscribers: [UUID: ([Float]) -> Void] = [:]
    private var tap: SystemAudioTap?
    private var analyser: BandAnalyser?
    private var timer: Timer?
    private var deviceObserver: NSObjectProtocol?

    /// Upper edge of each band in hertz; the first band starts at 40 Hz. Roughly logarithmic, so each bar covers
    /// a range that reads as a distinct part of the music rather than an equal slice of the spectrum.
    private static let bandEdges: [Float] = [160, 400, 1000, 2500, 8000]
    /// New levels a dozen times a second. The layers interpolate between them, so the eye sees a smooth bar
    /// either way and a higher rate buys nothing; the rate turned out not to drive the cost at all, which sits
    /// in the tap itself.
    private static let refreshInterval: TimeInterval = 1.0 / 12

    public init() {}

    /// Called with a fresh set of levels a dozen times a second while the tap is running, and once with the
    /// current set right away.
    @discardableResult
    public func subscribe(_ handler: @escaping ([Float]) -> Void) -> UUID {
        let token = UUID()
        subscribers[token] = handler
        handler(levels)
        return token
    }

    public func unsubscribe(_ token: UUID) {
        subscribers[token] = nil
    }

    private func start() {
        guard tap == nil else { return }
        let tap = SystemAudioTap()
        guard tap.start() else {
            NSLog("audio levels: could not tap system audio")
            return
        }
        self.tap = tap
        analyser = BandAnalyser(sampleRate: tap.sampleRate, edges: Self.bandEdges)
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // The tap follows the default output device; a change means the old one has to be rebuilt.
        deviceObserver = NotificationCenter.default.addObserver(
            forName: SystemAudioTap.defaultDeviceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        deviceObserver = nil
        tap?.stop()
        tap = nil
        analyser = nil
        isRunning = false
        levels = [Float](repeating: 0, count: Self.bandCount)
        subscribers.values.forEach { $0(levels) }
    }

    private func rebuild() {
        guard isEnabled else { return }
        stop()
        start()
    }

    private func refresh() {
        guard let tap, let analyser else { return }
        let samples = tap.latestSamples()
        guard !samples.isEmpty else { return }
        levels = analyser.levels(of: samples)
        subscribers.values.forEach { $0(levels) }
    }
}

/// Turns a block of samples into smoothed band levels.
private final class BandAnalyser {
    /// A power of two: long enough to tell the low bands apart, short enough to follow a beat.
    private static let windowSize = 1024

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    /// First and last bin of each band.
    private let bins: [(lower: Int, upper: Int)]
    private var smoothed: [Float]

    /// A level rises almost at once and falls back quickly enough to follow a beat; a slow fall leaves every bar
    /// pinned near the top, and equal rates in both directions read as flickering rather than music.
    private static let attack: Float = 0.7
    private static let decay: Float = 0.35
    /// Decibels added per band going up. Music carries far less energy at the top of the spectrum, and without
    /// this the last bars would sit flat whatever is playing.
    private static let tiltPerBand: Float = 4
    /// The window of loudness the bar height spans. Narrow on purpose: it is the difference between passages that
    /// should show, not the whole range from silence to clipping, which no music covers.
    private static let quietDecibels: Float = -37
    private static let loudDecibels: Float = -4

    init(sampleRate: Double, edges: [Float]) {
        let log2n = vDSP_Length(log2(Float(Self.windowSize)))
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.windowSize, isHalfWindow: false)
        let binWidth = Float(sampleRate) / Float(Self.windowSize)
        var lower = max(1, Int(40 / binWidth))
        var result: [(Int, Int)] = []
        for edge in edges {
            let upper = min(Self.windowSize / 2 - 1, max(lower, Int(edge / binWidth)))
            result.append((lower, upper))
            lower = min(Self.windowSize / 2 - 1, upper + 1)
        }
        bins = result
        smoothed = [Float](repeating: 0, count: edges.count)
    }

    func levels(of samples: [Float]) -> [Float] {
        guard samples.count >= Self.windowSize else { return smoothed }
        var windowed = [Float](repeating: 0, count: Self.windowSize)
        let start = samples.count - Self.windowSize
        vDSP.multiply(Array(samples[start..<samples.count]), window, result: &windowed)

        var real = [Float](repeating: 0, count: Self.windowSize / 2)
        var imaginary = [Float](repeating: 0, count: Self.windowSize / 2)
        var magnitudes = [Float](repeating: 0, count: Self.windowSize / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(Self.windowSize / 2))
                }
                fft.forward(input: split, output: &split)
                vDSP.absolute(split, result: &magnitudes)
            }
        }

        var result = smoothed
        for (index, band) in bins.enumerated() {
            let slice = magnitudes[band.lower...band.upper]
            // The loudest bin of a band, not its average: a single strong note should raise the bar rather than
            // be flattened by the quiet bins beside it.
            let peak = slice.max() ?? 0
            let scaled = peak / Float(Self.windowSize / 4)
            // Loudness is logarithmic, so the height follows decibels rather than amplitude.
            let decibels = 20 * log10(max(scaled, 1e-6)) + Self.tiltPerBand * Float(index)
            let span = Self.loudDecibels - Self.quietDecibels
            let level = min(max((decibels - Self.quietDecibels) / span, 0), 1)
            let rate = level > smoothed[index] ? Self.attack : Self.decay
            result[index] = smoothed[index] + (level - smoothed[index]) * rate
        }
        smoothed = result
        return result
    }
}

/// Owns the process tap and the private aggregate device that carries it, and keeps the newest samples for the
/// analyser. Not main-actor: the audio callback arrives on a real-time thread, so the buffer is guarded by a
/// lock and nothing here touches the UI.
private final class SystemAudioTap: @unchecked Sendable {
    static let defaultDeviceChanged = Notification.Name("com.d0lim.garakuta.audioTap.defaultDeviceChanged")

    /// Two analysis windows' worth, so a late read still finds a full window.
    private static let ringSize = 4096
    private static let scratchSize = 8192

    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: SystemAudioTap.ringSize)
    private var writeIndex = 0
    private var filled = 0
    /// Reused by the audio callback, which must not allocate. Generous: a callback delivers a few hundred frames.
    private var scratch = [Float](repeating: 0, count: SystemAudioTap.scratchSize)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// The listener block, kept so the same one can be removed again.
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private(set) var sampleRate: Double = 48_000

    private static func deviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    func start() -> Bool {
        // Everything the Mac plays, mixed to stereo. Our own output is not excluded because the app plays nothing.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Garakuta now-playing levels"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else { return false }

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }
        let channels = max(1, Int(format.mChannelsPerFrame))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        // An aggregate device is the only way to read a tap, but it needs no sub-devices: with none, nothing of
        // the user's playback is routed through it.
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Garakuta Levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else {
            cleanUp()
            return false
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { [weak self] _, input, _, _, _ in
            self?.received(input, channels: channels, interleaved: interleaved)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else {
            cleanUp()
            return false
        }
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            NotificationCenter.default.post(name: Self.defaultDeviceChanged, object: nil)
        }
        var address = Self.deviceAddress()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
        deviceListener = listener
        return true
    }

    func stop() {
        if let deviceListener {
            var address = Self.deviceAddress()
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, deviceListener)
            self.deviceListener = nil
        }
        cleanUp()
    }

    private func cleanUp() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Mixes the callback's buffers down to mono and appends them to the ring. Real-time thread: no allocation and
    /// no per-sample work, just two vector passes and a copy, so the tap costs the audio thread almost nothing.
    /// More than two channels contribute their first two, which is plenty for a level.
    private func received(_ input: UnsafePointer<AudioBufferList>, channels: Int, interleaved: Bool) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        lock.lock()
        defer { lock.unlock() }
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let floats = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            var frames = 0
            if interleaved && channels > 1 {
                frames = min(floats / channels, Self.scratchSize)
                scratch.withUnsafeMutableBufferPointer { out in
                    let stride = vDSP_Stride(channels)
                    vDSP_vadd(samples, stride, samples + 1, stride, out.baseAddress!, 1, vDSP_Length(frames))
                    var half: Float = 0.5
                    vDSP_vsmul(out.baseAddress!, 1, &half, out.baseAddress!, 1, vDSP_Length(frames))
                }
            } else {
                frames = min(floats, Self.scratchSize)
                scratch.withUnsafeMutableBufferPointer { out in
                    out.baseAddress!.update(from: samples, count: frames)
                }
            }
            append(frames)
            // One buffer is one channel when the format is not interleaved, and one is enough for a level.
            if !interleaved { break }
        }
    }

    /// Copies the first `count` scratch samples into the ring, wrapping at most once.
    private func append(_ count: Int) {
        var remaining = count
        var offset = 0
        while remaining > 0 {
            let chunk = min(remaining, Self.ringSize - writeIndex)
            ring.withUnsafeMutableBufferPointer { destination in
                scratch.withUnsafeBufferPointer { source in
                    destination.baseAddress!.advanced(by: writeIndex)
                        .update(from: source.baseAddress!.advanced(by: offset), count: chunk)
                }
            }
            writeIndex = (writeIndex + chunk) % Self.ringSize
            filled = min(Self.ringSize, filled + chunk)
            remaining -= chunk
            offset += chunk
        }
    }

    /// The newest samples, oldest first. Empty until the ring has filled once.
    func latestSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard filled == Self.ringSize else { return [] }
        return Array(ring[writeIndex..<Self.ringSize]) + Array(ring[0..<writeIndex])
    }
}
