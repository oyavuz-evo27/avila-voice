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
    @State private var ringPulse = false

    // Manual growth animation: implicit SwiftUI animations do not render for
    // phase-driven layout in this panel (verified frame-by-frame with the
    // screenshot probe). The size is therefore ticked explicitly per display
    // frame — the same mechanism as the waveform, which demonstrably animates.
    @State private var growFrom = CGSize(width: 42, height: 11)
    @State private var growTo = CGSize(width: 42, height: 11)
    @State private var growStart: Date?
    /// While set, the recording ring stays attached to the SHRINKING capsule and
    /// fades out — removing it instantly left only the near-invisible dark capsule,
    /// which made the stop look like a hard cut on dark backgrounds.
    @State private var ringFadeStart: Date?
    private static let growDuration: TimeInterval = 0.38
    private static let ringFadeDuration: TimeInterval = 0.35

    private func currentPillSize(at date: Date) -> CGSize {
        guard let growStart else { return growTo }
        let t = min(1, max(0, date.timeIntervalSince(growStart) / Self.growDuration))
        // easeOutBack — decisive growth with a slight Dynamic-Island overshoot.
        let s = 1.15
        let u = t - 1
        let eased = 1 + (s + 1) * u * u * u + s * u * u
        return CGSize(width: growFrom.width + (growTo.width - growFrom.width) * eased,
                      height: growFrom.height + (growTo.height - growFrom.height) * eased)
    }

    private var growFinished: Bool {
        if let ringFadeStart,
           Date().timeIntervalSince(ringFadeStart) <= Self.ringFadeDuration + 0.05 {
            return false // keep ticking while the ring fades out
        }
        guard let growStart else { return true }
        return Date().timeIntervalSince(growStart) > Self.growDuration + 0.05
    }

    /// 1 while recording; eases to 0 alongside the shrink after recording ends.
    private func ringOpacity(at date: Date) -> Double {
        if isRecording { return 1 }
        guard let ringFadeStart else { return 0 }
        let t = date.timeIntervalSince(ringFadeStart) / Self.ringFadeDuration
        guard t < 1 else { return 0 }
        let u = 1 - t
        return u * u // easeOut fade
    }
    @State private var idleGlow: Double = 0
    @State private var idlePulseTask: Task<Void, Never>?
    @State private var bars: [CGFloat] = Array(repeating: 0, count: 17)

    /// Center-weighted envelope: middle bars swing the most, outer ones stay calm.
    private static let barWeights: [CGFloat] = {
        let n = 17
        let mid = CGFloat(n - 1) / 2
        return (0..<n).map { i in
            let x = (CGFloat(i) - mid) / mid
            return 0.30 + 0.70 * exp(-3 * x * x)
        }
    }()

    /// Dynamic-Island choreography: the capsule GROWS as the hero; the old content
    /// vanishes instantly-ish, the new one fades in only once the shape has room.
    private static let contentSwap: AnyTransition = .asymmetric(
        insertion: .opacity.animation(.easeIn(duration: 0.16).delay(0.12)),
        removal: .opacity.animation(.easeOut(duration: 0.05)))

    /// Only the waveform lingers a little on its way out (stop reads as a snap
    /// otherwise); everything else vanishes crisply.
    private static let waveformSwap: AnyTransition = .asymmetric(
        insertion: .opacity.animation(.easeIn(duration: 0.16).delay(0.12)),
        removal: .opacity.animation(.easeOut(duration: 0.18)))

    private let warmOrange = Color(red: 1.00, green: 0.45, blue: 0.25)
    private let warmPink = Color(red: 0.96, green: 0.22, blue: 0.44)
    private let warmPurple = Color(red: 0.62, green: 0.32, blue: 0.85)

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

            // The ZStack itself centers the pill — symmetric growth from the middle
            // is guaranteed by construction (Dynamic-Island style), the bottom edge
            // stays anchored. The accessories ride outward with the growing width.
            ZStack(alignment: .bottom) {
                pill

                HStack(spacing: 4) {
                    accessory(leftIcon, hovering: hoverCopy, help: leftHelp)
                        .opacity(showAccessories ? 1 : 0)
                        .scaleEffect(showAccessories ? 1 : 0.6)
                        .allowsHitTesting(showAccessories)
                        .onHover { over in hoverCopy = over; updateVisibility() }
                        .onTapGesture { leftAction() }

                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: growFinished)) { timeline in
                        Color.clear
                            .frame(width: currentPillSize(at: timeline.date).width + 18, height: 1)
                    }
                    .allowsHitTesting(false)

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
                .padding(.bottom, 8)
                // showAccessories changes are animated at the source (updateVisibility)
                // — an .animation(value:) modifier here would strip the phase-growth
                // animation from the accessories.
            }
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Phase-change animation sits ABOVE the row so the LAYOUT animates too —
        // otherwise sibling positions jump to their final spots while the pill is
        // still interpolating, which reads as lopsided growth.
        .onChange(of: state.audioLevel) { _, level in
            updateBars(level: CGFloat(level))
        }
        .onChange(of: state.phase) { oldPhase, newPhase in
            let now = Date()
            growFrom = currentPillSize(at: now) // retarget smoothly mid-flight
            growTo = pillSize
            growStart = now
            if oldPhase == .recording { ringFadeStart = now }
            if newPhase == .recording { ringFadeStart = nil }
        }
        .onAppear {
            growFrom = pillSize
            growTo = pillSize
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

    /// One container whose size the spring animates — the abrupt idle→recording jump
    /// becomes a smooth growth, contents crossfade.
    private var pillSize: CGSize {
        switch state.phase {
        case .recording: CGSize(width: 84, height: 20)
        case .processing, .result, .error: CGSize(width: 52, height: 17)
        case .idle: CGSize(width: 42, height: 11)
        }
    }

    private var pill: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: growFinished)) { timeline in
            pillBody(size: currentPillSize(at: timeline.date), date: timeline.date)
        }
        .padding(6) // invisible margin: enlarges the click/hover target (Fitts)
        .contentShape(Rectangle())
        .onHover { over in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                hoverPill = over
            }
            updateVisibility()
        }
        .onTapGesture {
            // Click on the pill = toggle recording (same as a hotkey tap).
            switch state.phase {
            case .recording: state.finishRecording()
            case .processing: break
            default: state.startRecording()
            }
        }
    }

    private func pillBody(size: CGSize, date: Date) -> some View {
        ZStack {
            switch state.phase {
            case .recording:
                waveform
                    .transition(Self.waveformSwap)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .transition(Self.contentSwap)
            case .result(let inserted):
                Image(systemName: inserted ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11, weight: .bold))
                    .transition(Self.contentSwap)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(warmPink)
                    .transition(Self.contentSwap)
            case .idle:
                idleLine
                    .transition(Self.contentSwap)
            }
        }
        .frame(width: size.width, height: size.height)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(hoverPill ? 0.64 : 0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(hoverPill ? 0.25 : 0.12)))
        .overlay {
            // The ring stays in the tree while fading, so it TRACKS the shrinking
            // capsule instead of freezing at the old size — that contracting colored
            // ring IS the visible stop animation on dark backgrounds.
            let opacity = ringOpacity(at: date)
            if opacity > 0 {
                recordingGlow
                    .opacity(opacity)
            }
        }
        .scaleEffect(hoverPill ? 1.03 : 1.0)
    }

    /// The idle line: gray at rest. Every few seconds the WHOLE bar lights up once
    /// in warm orange → pink → purple, then slowly fades back to gray — subtle,
    /// but noticeable.
    private var idleLine: some View {
        Capsule()
            .fill(.white.opacity(hoverPill ? 0.55 : 0.35))
            .overlay {
                Capsule()
                    .fill(LinearGradient(colors: [warmOrange, warmPink, warmPurple],
                                         startPoint: .leading, endPoint: .trailing))
                    .shadow(color: warmPink.opacity(0.55 * idleGlow), radius: 4)
                    .opacity(idleGlow)
            }
            .frame(width: 26, height: 4)
            .onAppear {
                idlePulseTask?.cancel()
                idlePulseTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    while !Task.isCancelled {
                        withAnimation(.easeIn(duration: 0.7)) { idleGlow = 1 }
                        try? await Task.sleep(for: .seconds(0.9))
                        withAnimation(.easeOut(duration: 1.7)) { idleGlow = 0 }
                        try? await Task.sleep(for: .seconds(4.5))
                    }
                }
            }
            .onDisappear {
                idlePulseTask?.cancel()
                idlePulseTask = nil
                idleGlow = 0
            }
    }

    /// The full border carries the warm three-color gradient (orange → pink →
    /// purple), closed into a seamless ring that rotates very slowly.
    private var recordingGlow: some View {
        Capsule()
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: [
                        warmOrange, warmPink, warmPurple, warmPink, warmOrange,
                    ]),
                    center: .center,
                    angle: .degrees(orbitA)),
                lineWidth: 1.5)
            .opacity(ringPulse ? 1.0 : 0.45)
            .shadow(color: warmPink.opacity(ringPulse ? 0.4 : 0.15),
                    radius: ringPulse ? 6 : 3)
            .onAppear {
                // Reset and animate in SEPARATE update cycles — otherwise the second
                // recording nets to "no change" and the animations freeze.
                orbitA = 0
                ringPulse = false
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: 14.0).repeatForever(autoreverses: false)) {
                        orbitA = 360
                    }
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        ringPulse = true
                    }
                }
            }
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
