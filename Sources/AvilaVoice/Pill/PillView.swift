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
    @State private var orbitA: Double = 0
    @State private var orbitB: Double = 180
    @State private var idlePulse = false
    @State private var bars: [CGFloat] = Array(repeating: 0, count: 19)

    /// Center-weighted envelope: middle bars swing the most, outer ones stay calm.
    private static let barWeights: [CGFloat] = {
        let n = 19
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

            // Bubble zone above the row: error, transcript preview, or mode chips.
            ZStack {
                if case .error(let message) = state.phase {
                    errorBubble(message)
                        .transition(.opacity)
                } else if showTranscriptBubble, let last = state.history.last {
                    transcriptBubble(last.finalText)
                        .onHover { over in hoverBubble = over; updateVisibility() }
                        .transition(.opacity)
                }
                if modeListOpen {
                    modeChips
                        .transition(.opacity)
                }
            }

            HStack(spacing: 4) {
                accessory(leftIcon, hovering: hoverCopy, help: leftHelp)
                    .opacity(showAccessories ? 1 : 0)
                    .scaleEffect(showAccessories ? 1 : 0.6)
                    .allowsHitTesting(showAccessories)
                    .onHover { over in hoverCopy = over; updateVisibility() }
                    .onTapGesture { leftAction() }

                pill

                accessory(text: L("Modes"), hovering: hoverModes)
                    .help(L("Modes"))
                    .accessibilityLabel(L("Modes"))
                    .opacity(showAccessories ? 1 : 0)
                    .scaleEffect(showAccessories ? 1 : 0.6)
                    .allowsHitTesting(showAccessories)
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

    private var isProcessing: Bool {
        if case .processing = state.phase { return true }
        return false
    }

    /// The transcript preview opens when hovering the copy circle — and, right after a
    /// dictation (result state), already when hovering the pill itself.
    private var showTranscriptBubble: Bool {
        guard !isRecording, !isProcessing else { return false }
        if hoverCopy || hoverBubble { return true }
        if case .result = state.phase { return hoverPill }
        return false
    }

    // MARK: - Accessories (circles left and right of the pill)

    private var leftIcon: String {
        if isRecording || isProcessing { return "xmark" }
        return copiedFlash ? "checkmark" : "doc.on.doc"
    }

    private var leftHelp: String {
        (isRecording || isProcessing) ? L("Cancel") : L("Copy")
    }

    private func leftAction() {
        if isRecording {
            state.cancelRecording()
        } else if isProcessing {
            state.cancelProcessing()
        } else {
            state.copyLastResult()
            copiedFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                copiedFlash = false
            }
        }
    }

    private func accessory(_ icon: String, hovering: Bool, help: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 23, height: 23)
            .background(.black.opacity(hovering ? 0.64 : 0.82), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(hovering ? 0.25 : 0.12)))
            .contentShape(Circle())
            .help(help)
            .accessibilityLabel(help)
    }

    private func accessory(text: String, hovering: Bool) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(.black.opacity(hovering ? 0.64 : 0.82), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.25 : 0.12)))
            .contentShape(Capsule())
    }

    // MARK: - Bubbles

    private func transcriptBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .lineLimit(8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 300, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
    }

    private func errorBubble(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(warmPink)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(warmPink.opacity(0.4)))
    }

    /// Mode chips fit in one row when possible; with many custom modes they scroll
    /// horizontally instead of being clipped invisibly.
    private var modeChips: some View {
        ViewThatFits(in: .horizontal) {
            chipsRow
            ScrollView(.horizontal, showsIndicators: false) {
                chipsRow.padding(.horizontal, 2)
            }
            .frame(width: 350)
        }
    }

    private var chipsRow: some View {
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
                                : AnyShapeStyle(.ultraThinMaterial),
                            in: Capsule())
                        .foregroundStyle(
                            state.selectedModeID == mode.id
                                ? AnyShapeStyle(.black)
                                : AnyShapeStyle(.primary))
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
                    .frame(width: 92, height: 20)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(width: 52, height: 17)
            case .result(let inserted):
                Image(systemName: inserted ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 52, height: 17)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(warmPink)
                    .frame(width: 52, height: 17)
            case .idle:
                idleLine
                    .frame(width: 42, height: 11)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(hoverPill ? 0.64 : 0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(hoverPill ? 0.25 : 0.12)))
        .overlay {
            if isRecording { recordingGlow }
        }
        .scaleEffect(hoverPill ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hoverPill)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.phase)
        .padding(6) // invisible margin: enlarges the click/hover target (Fitts)
        .contentShape(Rectangle())
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

    /// The idle line: stays gray — its outline breathes a soft warm glow that slowly
    /// appears and fades again.
    private var idleLine: some View {
        Capsule()
            .fill(.white.opacity(hoverPill ? 0.55 : 0.35))
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(colors: [warmOrange, warmPink],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: 0.8)
                    .shadow(color: warmPink.opacity(0.4), radius: 2.5)
                    .opacity(idlePulse ? 0.6 : 0.0)
            }
            .frame(width: 26, height: 4)
            .onAppear {
                // Reset and animate in SEPARATE update cycles — otherwise the second
                // appearance nets to "no change" and repeatForever never starts.
                idlePulse = false
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                        idlePulse = true
                    }
                }
            }
    }

    /// Two soft shimmer segments drifting slowly around the pill border — at slightly
    /// different speeds, so they are never perfectly parallel.
    private var recordingGlow: some View {
        ZStack {
            orbitStroke(angle: orbitA)
            orbitStroke(angle: orbitB)
        }
        .shadow(color: warmPink.opacity(0.22), radius: 4)
        .onAppear {
            // Reset and animate in SEPARATE update cycles — otherwise the second
            // recording nets to "no change" and the shimmer freezes.
            orbitA = 0
            orbitB = 180
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 12.0).repeatForever(autoreverses: false)) {
                    orbitA = 360
                }
                withAnimation(.linear(duration: 17.0).repeatForever(autoreverses: false)) {
                    orbitB = 540
                }
            }
        }
    }

    /// One gently fading gradient segment (~a quarter of the border).
    private func orbitStroke(angle: Double) -> some View {
        Capsule()
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: warmOrange.opacity(0.0), location: 0.04),
                        .init(color: warmOrange.opacity(0.55), location: 0.13),
                        .init(color: warmPink.opacity(0.55), location: 0.22),
                        .init(color: warmPink.opacity(0.0), location: 0.30),
                        .init(color: .clear, location: 1.00),
                    ]),
                    center: .center,
                    angle: .degrees(angle)),
                lineWidth: 1.5)
    }

    /// Live waveform: every bar reflects the current input level (no scrolling
    /// history). Quiet input = a flat line; speech makes all bars dance, the middle
    /// more than the edges.
    private func updateBars(level: CGFloat) {
        for i in bars.indices {
            let target = level * Self.barWeights[i] * CGFloat.random(in: 0.85...1.0)
            let current = bars[i]
            // Fast swell, slow decay — the Wispr-style breathing motion.
            let blend: CGFloat = target > current ? 0.35 : 0.12
            bars[i] = current + (target - current) * blend
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5,
                           height: max(2, bars[i] * 15))
            }
        }
        .animation(.easeOut(duration: 0.22), value: bars)
    }
}
