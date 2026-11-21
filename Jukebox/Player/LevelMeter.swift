// The music's levels, for the Equalizer player bar (MiniPlayerRecord.swift):
// "equalizer bars er achter zetten die echt zijn" (the photographer, 21
// November 2026). Real, where the sound passes through this device:
//
//   - A file from the server or from the phone (progressive HTTP, a song
//     kept offline): an MTAudioProcessingTap on the item's audio mix hands
//     each buffer the engine renders to `take`, which keeps the last 1024
//     samples of the first channel. The bar asks `bands()` up to 30 times a
//     second, and that runs the FFT (vDSP) on the main thread, off the audio
//     thread, and folds it into log-spaced bands.
//   - A Jellyfin transcode streams as HLS: its asset has no audio track to
//     tap, so `attach` finds none and `bands()` stays nil.
//   - Play On (Chromecast, Sonos, a UPnP renderer): this engine is quiet,
//     no buffers come, `bands()` is nil.
//   - AirPlay: the tap may still see the buffers, but ahead of what the room
//     hears by the receiver's latency, so the bar does not take them there.
//
// Where it is nil the bar moves by a calm envelope of its own instead
// (EqualizerBars). The tap is on only while Equalizer is the chosen bar, so
// the default bar's audio path is as it was; chosen in the middle of a song,
// the next song is the first measured.

import Accelerate
import AVFoundation
import MediaToolbox
import os

nonisolated final class LevelMeter: @unchecked Sendable {
    static let shared = LevelMeter()

    /// Samples in one look: 1024 at 44.1 kHz is 23 ms, bins 43 Hz apart.
    static let size = 1024
    private static let log2Size = vDSP_Length(10)
    /// The bands' outer edges, Hz: a kick drum to the cymbals' air.
    static let lowest: Float = 50
    static let highest: Float = 14_000
    /// The calibration knobs: the dB that reads as empty and as full, and
    /// the lift per octave up, as music's energy falls about that much
    /// (pink), so the treble moves as the bass does.
    static let floorDB: Float = -62
    static let ceilingDB: Float = -14
    static let tiltPerOctave: Float = 3

    private struct Shared {
        var samples = [Float](repeating: 0, count: LevelMeter.size)
        var write = 0
        var rate: Double = 44_100
        /// When the last buffer came, by the host clock.
        var stamp: UInt64 = 0
        /// Anything on screen that wants the levels (one per bar shown).
        var watchers = 0
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private let setup = vDSP_create_fftsetup(LevelMeter.log2Size, FFTRadix(kFFTRadix2))
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                     count: LevelMeter.size, isHalfWindow: false)

    // MARK: The tap

    /// A tap on the item's first audio track, once its tracks are known.
    /// None for HLS (no tracks), and then the bar falls back.
    func attach(to item: AVPlayerItem) {
        let asset = item.asset
        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let tap = Self.makeTap() else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            await MainActor.run { item.audioMix = mix }
        }
    }

    /// The tap's callbacks, made here, off the main actor (the app's
    /// default), as AVFoundation calls them on its audio thread. Each tap
    /// keeps, in its storage, whether its samples are Float32 and one
    /// buffer a channel: what AVPlayer hands a tap. Anything else is left
    /// unmeasured, never unplayed: process always fetches the source.
    private static func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: { _, _, storage in
                let readable = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
                readable.initialize(to: false)
                storage.pointee = UnsafeMutableRawPointer(readable)
            },
            finalize: { tap in
                MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: Bool.self).deallocate()
            },
            prepare: { tap, _, format in
                let flags = format.pointee.mFormatFlags
                let readable = flags & kAudioFormatFlagIsFloat != 0
                    && flags & kAudioFormatFlagIsNonInterleaved != 0
                    && format.pointee.mBitsPerChannel == 32
                MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: Bool.self).pointee = readable
                LevelMeter.shared.setRate(format.pointee.mSampleRate)
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
                guard status == noErr,
                      MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: Bool.self).pointee else { return }
                LevelMeter.shared.take(buffers, frames: framesOut.pointee)
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }

    private func setRate(_ rate: Double) {
        guard rate > 0 else { return }
        _ = shared.withLockIfAvailable { $0.rate = rate }
    }

    /// The audio thread's part: copy, nothing more. Never waits for the
    /// lock: a buffer missed while the bar reads is one look the less.
    private func take(_ list: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let first = buffers.first, let data = first.mData, frames > 0 else { return }
        let count = min(Int(frames), Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        let samples = data.assumingMemoryBound(to: Float.self)
        _ = shared.withLockIfAvailable { state in
            guard state.watchers > 0 else { return }
            let kept = min(count, Self.size)
            let from = samples + (count - kept)
            for index in 0 ..< kept {
                state.samples[state.write] = from[index]
                state.write = (state.write + 1) % Self.size
            }
            state.stamp = mach_absolute_time()
        }
    }

    // MARK: The bar's part

    /// A bar on screen and wanting levels, or gone (off screen, the app in
    /// the background, Now Playing over it): no copying while none wants.
    func watch(_ on: Bool) {
        shared.withLock { $0.watchers = max(0, $0.watchers + (on ? 1 : -1)) }
    }

    /// The last look's levels, 0 to 1, low to high: nil when no buffer came
    /// in the last third of a second (paused, HLS, Play On).
    func bands(_ count: Int) -> [Float]? {
        guard let setup else { return nil }
        let (samples, rate, fresh) = shared.withLock { state in
            let age = Self.seconds(since: state.stamp)
            let ordered = Array(state.samples[state.write...] + state.samples[..<state.write])
            return (ordered, state.rate, state.stamp != 0 && age < 0.33)
        }
        guard fresh else { return nil }

        let half = Self.size / 2
        let windowed = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPart in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPart in
                var split = DSPSplitComplex(realp: realPart.baseAddress!, imagp: imaginaryPart.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2Size, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        // A full-scale sine in one bin is (size / 2)² after zrip's doubling.
        let fullScale = Float(Self.size * Self.size) / 4
        return Self.fold(power, fullScale: fullScale, rate: Float(rate), into: count)
    }

    /// The bins into `count` bands spaced evenly by octave, each its mean
    /// power in dB, tilted, between floor and ceiling.
    static func fold(_ power: [Float], fullScale: Float, rate: Float, into count: Int) -> [Float] {
        let binHz = rate / Float(size)
        let octaves = log2(highest / lowest)
        return (0 ..< count).map { band in
            let low = lowest * pow(2, octaves * Float(band) / Float(count))
            let high = lowest * pow(2, octaves * Float(band + 1) / Float(count))
            let first = max(1, Int(low / binHz))
            let last = min(power.count - 1, max(first, Int(high / binHz)))
            var sum: Float = 0
            for bin in first ... last { sum += power[bin] }
            let mean = sum / Float(last - first + 1)
            let centre = (low * high).squareRoot()
            let db = 10 * log10(mean / fullScale + 1e-12) + tiltPerOctave * log2(centre / 1000)
            return min(1, max(0, (db - floorDB) / (ceilingDB - floorDB)))
        }
    }

    private static func seconds(since stamp: UInt64) -> Double {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        let ticks = mach_absolute_time() &- stamp
        return Double(ticks) * Double(base.numer) / Double(base.denom) / 1_000_000_000
    }
}
