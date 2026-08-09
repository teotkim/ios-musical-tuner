import SwiftUI

struct ContentView: View {
    @StateObject private var tuner = TunerViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.12),
                    Color(red: 0.10, green: 0.13, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                headerView

                Spacer(minLength: 8)

                VStack(spacing: 18) {
                    pitchCard(
                        title: "LOWER NOTE",
                        note: tuner.lowerDisplayNote,
                        frequency: tuner.lowerFrequency,
                        cents: tuner.lowerCents,
                        strength: tuner.lowerStrength,
                        message: tuner.lowerMessage,
                        color: tuner.lowerColor
                    )

                    pitchCard(
                        title: "UPPER NOTE",
                        note: tuner.upperDisplayNote,
                        frequency: tuner.upperFrequency,
                        cents: tuner.upperCents,
                        strength: tuner.upperStrength,
                        message: tuner.upperMessage,
                        color: tuner.upperColor
                    )
                }

                statusView

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .onAppear {
                tuner.start()
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            Text("DoubleStop")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 28)
        }
    }

    private var statusView: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(tuner.overallColor)
                .frame(width: 12, height: 12)
                .shadow(color: tuner.overallColor.opacity(0.8), radius: 8)

            Text(tuner.overallMessage)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private func pitchCard(
        title: String,
        note: String,
        frequency: Double,
        cents: Double,
        strength: Double,
        message: String,
        color: Color
    ) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Text(message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note)
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)

                    Text(String(format: "%.2f Hz", frequency))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                VStack(spacing: 6) {
                    Text(centsText(cents))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(color)

                    Text("cents")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            tuningMeter(cents: cents, color: color)

            strengthBar(strength: strength)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.white.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    private func tuningMeter(cents: Double, color: Color) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = max(min(cents, 50), -50)
            let position = width / 2 + CGFloat(clamped / 100.0) * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.14))
                    .frame(height: 10)

                Rectangle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 2, height: 24)
                    .position(x: width / 2, y: 5)

                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .shadow(color: color.opacity(0.8), radius: 8)
                    .position(x: position, y: 5)
            }
        }
        .frame(height: 24)
    }

    private func strengthBar(strength: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Signal")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                Text("\(Int(min(strength, 1.0) * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            ProgressView(value: min(strength, 1.0))
                .tint(.white.opacity(0.85))
        }
    }

    private func centsText(_ cents: Double) -> String {
        if abs(cents) < 0.05 {
            return "0.0"
        }

        if cents > 0 {
            return String(format: "+%.1f", cents)
        } else {
            return String(format: "%.1f", cents)
        }
    }
}
