import SwiftUI

/// The pill: a small bar at rest. Hovering reveals two circular accessories —
/// copy (left, icon only; the last transcript appears as a bubble on hover) and
/// mode selection (right, opens a chip list). While recording, two warm gradient
/// segments orbit the pill border.
struct PillView: View {
    @EnvironmentObject var state: AppState
    @State private var hoverPill = false
    @State private var hoverCopy = false
    @State private var hoverModes = false
    @State private var hoverBubble = false
    @State private var showAccessories = false
    @State private var modeListOpen = false
    @State private var copiedFlash = false
    @State private var borderRotation: Double = 0
    @State private var bars: [CGFloat] = Array(repeating: 0, count: 21)

    /// Center-weighted envelope: middle bars swing the most, outer ones stay calm.
    private static let barWeights: [CGFloat] = {
        let n = 21
        let mid = CGFloat(n - 1) / 2
        return (0..<n).map { i in
            let x = (CGFloat(i) - mid) / mid
            return 0.30 + 0.70 * exp(-3 * x * x)
        }
    }()

    private let warmOrange = Color(red: 1.00, green: 0.45, blue: 0.25)
    private let warmPink = Color(red: 0.96, green: 0.22, blue: 0.44)

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            // Bubble zone above the row: transcript preview or mode chips.
            ZStack {
                if hoverCopy || hoverBubble, let last = state.history.last {
                    transcriptBubble(last.finalText)
                        .onHover { over in hoverBubble = over; updateVisibility() }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if modeListOpen {
                    modeChips
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            HStack(spacing: 8) {
                accessory(leftIcon, hovering: hoverCopy)
                    .opacity(showAccessories ? 1 : 0)
                    .scaleEffect(showAccessories ? 1 : 0.6)
                    .onHover { over in hoverCopy = over; updateVisibility() }
                    .onTapGesture { leftAction() }

                pill

                accessory(text: L("Modes"), hovering: hoverModes)
                    .opacity(showAccessories ? 1 : 0)
                    .scaleEffect(showAccessories ? 1 : 0.6)
                    .onHover { over in hoverModes = over; updateVisibility() }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            modeListOpen.toggle()
                        }
                    }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showAccessories)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: state.audioLevel) { _, level in
            updateBars(level: CGFloat(level))
        }
    }

    // MARK: - Hover bookkeeping

    private var anyHover: Bool { hoverPill || hoverCopy || hoverModes || hoverBubble }

    private func updateVisibility() {
        if anyHover {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                showAccessories = true
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !anyHover {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showAccessories = false
                        modeListOpen = false
                    }
                }
            }
        }
    }

    private var isRecording: Bool {
        if case .recording = state.phase { return true }
        return false
    }

    // MARK: - Accessories (circles left and right of the pill)

    private var leftIcon: String {
        if isRecording { return "xmark" }
        return copiedFlash ? "checkmark" : "doc.on.doc"
    }

    private func leftAction() {
        if isRecording {
            state.cancelRecording()
        } else {
            state.copyLastResult()
            copiedFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                copiedFlash = false
            }
        }
    }

    private func accessory(_ icon: String, hovering: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.black.opacity(hovering ? 0.64 : 0.82), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(hovering ? 0.25 : 0.12)))
            .contentShape(Circle())
    }

    private func accessory(text: String, hovering: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(.black.opacity(hovering ? 0.64 : 0.82), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.25 : 0.12)))
            .contentShape(Capsule())
    }

    // MARK: - Bubbles

    private func transcriptBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .lineLimit(8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 300, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
    }

    private var modeChips: some View {
        HStack(spacing: 4) {
            ForEach(state.modes) { mode in
                Button {
                    state.selectedModeID = mode.id
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        modeListOpen = false
                    }
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            state.selectedModeID == mode.id
                                ? AnyShapeStyle(.white.opacity(0.9))
                                : AnyShapeStyle(.black.opacity(0.82)),
                            in: Capsule())
                        .foregroundStyle(
                            state.selectedModeID == mode.id ? .black : .white)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - The pill itself

    private var pill: some View {
        Group {
            switch state.phase {
            case .recording:
                waveform
                    .frame(width: 130, height: 30)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60, height: 22)
            case .result(let inserted):
                Image(systemName: inserted ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 60, height: 22)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
                    .frame(width: 60, height: 22)
            case .idle:
                Capsule()
                    .fill(.white.opacity(hoverPill ? 0.55 : 0.35))
                    .frame(width: 36, height: 5)
                    .frame(width: 60, height: 14)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(hoverPill ? 0.64 : 0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(hoverPill ? 0.25 : 0.12)))
        .overlay {
            if isRecording { recordingGlow }
        }
        .scaleEffect(hoverPill ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hoverPill)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.phase)
        .contentShape(Capsule())
        .onHover { over in hoverPill = over; updateVisibility() }
        .onTapGesture {
            // Click on the pill = toggle recording (same as a hotkey tap).
            switch state.phase {
            case .recording: state.finishRecording()
            case .processing: break
            default: state.startRecording()
            }
        }
    }

    /// Two warm gradient segments orbiting the pill border — subtle, no full ring.
    private var recordingGlow: some View {
        Capsule()
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: warmOrange.opacity(0.9), location: 0.10),
                        .init(color: warmPink.opacity(0.9), location: 0.20),
                        .init(color: .clear, location: 0.30),
                        .init(color: .clear, location: 0.50),
                        .init(color: warmOrange.opacity(0.9), location: 0.60),
                        .init(color: warmPink.opacity(0.9), location: 0.70),
                        .init(color: .clear, location: 0.80),
                        .init(color: .clear, location: 1.00),
                    ]),
                    center: .center,
                    angle: .degrees(borderRotation)),
                lineWidth: 1.8)
            .shadow(color: warmPink.opacity(0.3), radius: 5)
            .onAppear {
                borderRotation = 0
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    borderRotation = 360
                }
            }
    }

    /// Live waveform: every bar reflects the current input level (no scrolling
    /// history). Quiet input = a flat line; speech makes all bars dance, the middle
    /// more than the edges.
    private func updateBars(level: CGFloat) {
        for i in bars.indices {
            let target = level * Self.barWeights[i] * CGFloat.random(in: 0.55...1.0)
            bars[i] = bars[i] * 0.45 + target * 0.55
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5,
                           height: max(3, bars[i] * 26))
            }
        }
        .animation(.linear(duration: 0.08), value: bars)
    }
}
