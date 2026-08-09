import Foundation
import AVFoundation
import SwiftUI
import Combine
import Accelerate

struct PitchCandidate {
    let midi: Int
    let noteName: String
    let targetFrequency: Double
    let detectedFrequency: Double
    let cents: Double
    let strength: Double
    let score: Double
}

class TunerViewModel: ObservableObject {
    private let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    @Published var lowerDisplayNote = "--"
    @Published var upperDisplayNote = "--"

    @Published var lowerFrequency: Double = 0
    @Published var upperFrequency: Double = 0

    @Published var lowerCents: Double = 0
    @Published var upperCents: Double = 0

    @Published var lowerStrength: Double = 0
    @Published var upperStrength: Double = 0

    @Published var lowerMessage = "Waiting..."
    @Published var upperMessage = "Waiting..."

    @Published var lowerColor: Color = .gray
    @Published var upperColor: Color = .gray

    @Published var overallMessage = "Listening..."
    @Published var overallColor: Color = .blue

    @Published var isListening = false

    private let audioEngine = AVAudioEngine()

    // Bigger FFT gives better low-frequency detail.
    private let fftSize = 32768

    // The mic gives smaller chunks, so we collect them here.
    private var audioSampleBuffer: [Float] = []

    // C1 to C7.
    private let lowestMidi = 24
    private let highestMidi = 96

    private var fftSetup: FFTSetup?
    private var window: [Float] = []

    // Accuracy improvement:
    // Store recent detections so one noisy frame does not instantly change the display.
    private var recentDetections: [[PitchCandidate]] = []
    private let smoothingFrameCount = 5

    init() {
        let log2Size = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2))

        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        stop()

        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func start() {
        if isListening {
            return
        }

        requestMicrophonePermission { allowed in
            guard allowed else {
                DispatchQueue.main.async {
                    self.overallMessage = "Microphone permission denied"
                    self.overallColor = .red
                }
                return
            }

            self.startAudioEngine()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { allowed in
                completion(allowed)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                completion(allowed)
            }
        }
    }

    private func startAudioEngine() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            print("Audio session error:", error)

            DispatchQueue.main.async {
                self.overallMessage = "Audio session error"
                self.overallColor = .red
            }
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)

        audioSampleBuffer.removeAll()
        recentDetections.removeAll()

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
            self.processAudio(buffer: buffer, sampleRate: format.sampleRate)
        }

        do {
            try audioEngine.start()

            DispatchQueue.main.async {
                self.isListening = true
                self.overallMessage = "Listening..."
                self.overallColor = .blue
            }
        } catch {
            print("Audio engine error:", error)

            DispatchQueue.main.async {
                self.overallMessage = "Audio engine error"
                self.overallColor = .red
            }
        }
    }

    private func processAudio(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }

        let frameLength = Int(buffer.frameLength)

        if frameLength == 0 {
            return
        }

        for i in 0..<frameLength {
            audioSampleBuffer.append(channelData[i])
        }

        if audioSampleBuffer.count < fftSize {
            return
        }

        if audioSampleBuffer.count > fftSize {
            audioSampleBuffer.removeFirst(audioSampleBuffer.count - fftSize)
        }

        let loudness = rmsLevel(array: audioSampleBuffer)

        if loudness < 0.00035 {
            recentDetections.removeAll()

            DispatchQueue.main.async {
                self.resetDisplay(message: "Play louder / move closer")
            }
            return
        }

        let detectedCandidates = audioSampleBuffer.withUnsafeBufferPointer { pointer -> [PitchCandidate] in
            guard let baseAddress = pointer.baseAddress else {
                return []
            }

            guard let magnitudes = makeSpectrumMagnitudes(
                data: baseAddress,
                count: fftSize
            ) else {
                return []
            }

            return detectTwoFundamentals(
                magnitudes: magnitudes,
                sampleRate: sampleRate,
                loudness: loudness
            )
        }

        let stableCandidates = smoothDetections(detectedCandidates)

        DispatchQueue.main.async {
            self.updateDisplay(with: stableCandidates)
        }
    }

    private func makeSpectrumMagnitudes(
        data: UnsafePointer<Float>,
        count: Int
    ) -> [Float]? {
        guard let fftSetup else {
            return nil
        }

        var samples = [Float](repeating: 0, count: fftSize)

        for i in 0..<fftSize {
            samples[i] = data[i]
        }

        // Remove DC offset.
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(fftSize))

        var negativeMean = -mean
        vDSP_vsadd(samples, 1, &negativeMean, &samples, 1, vDSP_Length(fftSize))

        // Apply Hann window.
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        let halfSize = fftSize / 2

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                samples.withUnsafeBufferPointer { samplePtr in
                    samplePtr.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: halfSize
                    ) { complexPtr in
                        vDSP_ctoz(
                            complexPtr,
                            2,
                            &splitComplex,
                            1,
                            vDSP_Length(halfSize)
                        )
                    }
                }

                let log2Size = vDSP_Length(log2(Float(fftSize)))

                vDSP_fft_zrip(
                    fftSetup,
                    &splitComplex,
                    1,
                    log2Size,
                    FFTDirection(FFT_FORWARD)
                )
            }
        }

        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeBufferPointer { realPtr in
            imag.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )

                vDSP_zvabs(
                    &splitComplex,
                    1,
                    &magnitudes,
                    1,
                    vDSP_Length(halfSize)
                )
            }
        }

        magnitudes[0] = 0

        return magnitudes
    }

    private func detectTwoFundamentals(
        magnitudes: [Float],
        sampleRate: Double,
        loudness: Double
    ) -> [PitchCandidate] {
        var candidates: [PitchCandidate] = []

        for midi in lowestMidi...highestMidi {
            let fundamental = frequencyForMidi(midi)

            let f1 = magnitudeAtFrequency(fundamental, magnitudes: magnitudes, sampleRate: sampleRate)
            let f2 = magnitudeAtFrequency(fundamental * 2.0, magnitudes: magnitudes, sampleRate: sampleRate)
            let f3 = magnitudeAtFrequency(fundamental * 3.0, magnitudes: magnitudes, sampleRate: sampleRate)
            let f4 = magnitudeAtFrequency(fundamental * 4.0, magnitudes: magnitudes, sampleRate: sampleRate)
            let f5 = magnitudeAtFrequency(fundamental * 5.0, magnitudes: magnitudes, sampleRate: sampleRate)

            let sub2 = magnitudeAtFrequency(fundamental / 2.0, magnitudes: magnitudes, sampleRate: sampleRate)
            let sub3 = magnitudeAtFrequency(fundamental / 3.0, magnitudes: magnitudes, sampleRate: sampleRate)

            var score = 0.0

            if fundamental < 220 {
                // Low notes often have weaker fundamentals,
                // so the harmonics matter more.
                score += 0.80 * f1
                score += 0.55 * f2
                score += 0.35 * f3
                score += 0.22 * f4
                score += 0.12 * f5

                score -= 0.35 * sub2
                score -= 0.20 * sub3
            } else {
                score += 1.00 * f1
                score += 0.35 * f2
                score += 0.20 * f3
                score += 0.10 * f4
                score += 0.05 * f5

                score -= 0.65 * sub2
                score -= 0.35 * sub3
            }

            if score < 0 {
                score = 0
            }

            let refined = refineFrequencyNear(
                fundamental,
                magnitudes: magnitudes,
                sampleRate: sampleRate
            )

            let cents = 1200.0 * log2(refined / fundamental)
            let normalizedStrength = min(max(score / 400.0, 0.0), 1.0)

            // Higher thresholds reduce fake notes/noise.
            let requiredScore = fundamental < 220 ? 10.0 : 18.0

            if score > requiredScore {
                candidates.append(
                    PitchCandidate(
                        midi: midi,
                        noteName: noteNameForMidi(midi),
                        targetFrequency: fundamental,
                        detectedFrequency: refined,
                        cents: cents,
                        strength: normalizedStrength,
                        score: score
                    )
                )
            }
        }

        let sorted = candidates.sorted { $0.score > $1.score }

        var chosen: [PitchCandidate] = []

        for candidate in sorted {
            let tooCloseToExisting = chosen.contains { existing in
                abs(existing.midi - candidate.midi) < 2
            }

            if tooCloseToExisting {
                continue
            }

            let likelyOctaveDuplicate = chosen.contains { existing in
                abs(abs(existing.midi - candidate.midi) - 12) <= 1
            }

            if likelyOctaveDuplicate {
                let strongerExisting = chosen.contains { existing in
                    existing.score > candidate.score * 1.8
                }

                if strongerExisting {
                    continue
                }
            }

            let likelyHarmonicDuplicate = chosen.contains { existing in
                let ratio = candidate.detectedFrequency / existing.detectedFrequency
                let nearSecondHarmonic = abs(ratio - 2.0) < 0.06
                let nearThirdHarmonic = abs(ratio - 3.0) < 0.08

                return (nearSecondHarmonic || nearThirdHarmonic) && existing.score > candidate.score * 1.5
            }

            if likelyHarmonicDuplicate {
                continue
            }

            chosen.append(candidate)

            if chosen.count == 2 {
                break
            }
        }

        return chosen.sorted { $0.detectedFrequency < $1.detectedFrequency }
    }

    private func smoothDetections(_ current: [PitchCandidate]) -> [PitchCandidate] {
        recentDetections.append(current)

        if recentDetections.count > smoothingFrameCount {
            recentDetections.removeFirst()
        }

        var grouped: [Int: [PitchCandidate]] = [:]

        for frame in recentDetections {
            for candidate in frame {
                grouped[candidate.midi, default: []].append(candidate)
            }
        }

        var stable: [PitchCandidate] = []

        for (midi, candidates) in grouped {
            // Require the note to appear in at least 3 recent frames.
            if candidates.count < 3 {
                continue
            }

            let averageFrequency = candidates.map { $0.detectedFrequency }.reduce(0, +) / Double(candidates.count)
            let averageCents = candidates.map { $0.cents }.reduce(0, +) / Double(candidates.count)
            let averageStrength = candidates.map { $0.strength }.reduce(0, +) / Double(candidates.count)
            let averageScore = candidates.map { $0.score }.reduce(0, +) / Double(candidates.count)

            guard let best = candidates.max(by: { $0.score < $1.score }) else {
                continue
            }

            stable.append(
                PitchCandidate(
                    midi: midi,
                    noteName: best.noteName,
                    targetFrequency: best.targetFrequency,
                    detectedFrequency: averageFrequency,
                    cents: averageCents,
                    strength: averageStrength,
                    score: averageScore
                )
            )
        }

        let sorted = stable.sorted { $0.score > $1.score }

        var chosen: [PitchCandidate] = []

        for candidate in sorted {
            let tooClose = chosen.contains { existing in
                abs(existing.midi - candidate.midi) < 2
            }

            if tooClose {
                continue
            }

            chosen.append(candidate)

            if chosen.count == 2 {
                break
            }
        }

        return chosen.sorted { $0.detectedFrequency < $1.detectedFrequency }
    }

    private func magnitudeAtFrequency(
        _ frequency: Double,
        magnitudes: [Float],
        sampleRate: Double
    ) -> Double {
        if frequency <= 20 || frequency >= sampleRate / 2.0 {
            return 0.0
        }

        let exactBin = frequency * Double(fftSize) / sampleRate
        let lowerBin = Int(floor(exactBin))
        let upperBin = lowerBin + 1

        if lowerBin < 0 || upperBin >= magnitudes.count {
            return 0.0
        }

        let fraction = exactBin - Double(lowerBin)

        let lowerMag = Double(magnitudes[lowerBin])
        let upperMag = Double(magnitudes[upperBin])

        return lowerMag * (1.0 - fraction) + upperMag * fraction
    }

    private func refineFrequencyNear(
        _ frequency: Double,
        magnitudes: [Float],
        sampleRate: Double
    ) -> Double {
        let centerBin = frequency * Double(fftSize) / sampleRate
        let centerIndex = Int(round(centerBin))

        let searchRadius = frequency < 220 ? 8 : 4

        var bestIndex = centerIndex
        var bestMagnitude = 0.0

        for index in (centerIndex - searchRadius)...(centerIndex + searchRadius) {
            if index <= 1 || index >= magnitudes.count - 1 {
                continue
            }

            let mag = Double(magnitudes[index])

            if mag > bestMagnitude {
                bestMagnitude = mag
                bestIndex = index
            }
        }

        if bestIndex <= 1 || bestIndex >= magnitudes.count - 1 {
            return frequency
        }

        let left = Double(magnitudes[bestIndex - 1])
        let center = Double(magnitudes[bestIndex])
        let right = Double(magnitudes[bestIndex + 1])

        let denominator = left - 2.0 * center + right

        var binOffset = 0.0

        if abs(denominator) > 0.000001 {
            binOffset = 0.5 * (left - right) / denominator
        }

        let refinedBin = Double(bestIndex) + binOffset
        return refinedBin * sampleRate / Double(fftSize)
    }

    private func rmsLevel(array: [Float]) -> Double {
        if array.isEmpty {
            return 0.0
        }

        var sum = 0.0

        for sample in array {
            let value = Double(sample)
            sum += value * value
        }

        return sqrt(sum / Double(array.count))
    }

    private func frequencyForMidi(_ midi: Int) -> Double {
        return 440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    private func noteNameForMidi(_ midi: Int) -> String {
        let note = noteNames[midi % 12]
        let octave = midi / 12 - 1
        return "\(note)\(octave)"
    }

    private func messageFor(cents: Double, strength: Double) -> (String, Color) {
        if strength < 0.12 {
            return ("Weak / not clear", .gray)
        }

        if abs(cents) < 5 {
            return ("In tune", .green)
        } else if cents > 0 {
            return ("Too sharp", .orange)
        } else {
            return ("Too flat", .red)
        }
    }

    private func updateDisplay(with candidates: [PitchCandidate]) {
        if candidates.isEmpty {
            resetDisplay(message: "No stable notes detected")
            return
        }

        let first = candidates[0]

        lowerDisplayNote = first.noteName
        lowerFrequency = first.detectedFrequency
        lowerCents = first.cents
        lowerStrength = first.strength

        let firstMessage = messageFor(cents: first.cents, strength: first.strength)
        lowerMessage = firstMessage.0
        lowerColor = firstMessage.1

        if candidates.count >= 2 {
            let second = candidates[1]

            upperDisplayNote = second.noteName
            upperFrequency = second.detectedFrequency
            upperCents = second.cents
            upperStrength = second.strength

            let secondMessage = messageFor(cents: second.cents, strength: second.strength)
            upperMessage = secondMessage.0
            upperColor = secondMessage.1

            if abs(first.cents) < 5 && abs(second.cents) < 5 {
                overallMessage = "Double stop in tune"
                overallColor = .green
            } else {
                overallMessage = "Adjust one or both notes"
                overallColor = .red
            }
        } else {
            upperDisplayNote = "--"
            upperFrequency = 0
            upperCents = 0
            upperStrength = 0
            upperMessage = "Second note missing"
            upperColor = .gray

            overallMessage = "Only one stable note detected"
            overallColor = .orange
        }
    }

    private func resetDisplay(message: String) {
        lowerDisplayNote = "--"
        upperDisplayNote = "--"

        lowerFrequency = 0
        upperFrequency = 0

        lowerCents = 0
        upperCents = 0

        lowerStrength = 0
        upperStrength = 0

        lowerMessage = "Not detected"
        upperMessage = "Not detected"

        lowerColor = .gray
        upperColor = .gray

        overallMessage = message
        overallColor = .gray
    }
}
