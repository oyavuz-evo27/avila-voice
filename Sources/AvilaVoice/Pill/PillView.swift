import SwiftUI

/// The pill: a small bar at rest that brightens and grows slightly when the mouse is
/// really over it, shows a live waveform with an elegant warm glow while recording,
/// and opens a compact panel (modes + last transcript) on hover.
struct PillView: View {
    @EnvironmentObject var state: AppState
    @State private var hoveringPill = false
    @State private var hoveringPanel = false
    @State private var showPanel = false
    @State private var glowPulse = false
    @State private var levelHistory: [Float] = Array(repeating: 0, count: 24)

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            if showPanel {
                hoverPanel
                    .onHover { over in
                        hoveringPanel = over
                        updatePanelVisibility()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            pill
                .onHover { over in
                    hoveringPill = over
                    updatePanelVisibility()
                }
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: state.audioLevel) { _, level in
            levelHistory.removeFirst()
            levelHistory.append(level)
        }
    }

    /// The panel opens only while the mouse is truly over pill or panel; it closes with
    /// a short grace period so the mouse can travel between the two.
    private func updatePanelVisibility() {
        if hoveringPill || hoveringPanel {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { showPanel = true }
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !hoveringPill && !hoveringPanel {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showPanel = false
                    }
                }
            }
        }
    }

    private var isRecording: Bool {
        if case .recording = state.phase { return true }
        return false
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
                    .fill(.white.opacity(hoveringPill ? 0.55 : 0.35))
                    .frame(width: 36, height: 5)
                    .frame(width: 60, height: 14)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(hoveringPill ? 0.64 : 0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(hoveringPill ? 0.25 : 0.12)))
        .overlay {
            if isRecording { recordingGlow }
        }
        .scaleEffect(hoveringPill ? 1.07 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveringPill)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.phase)
        .contentShape(Capsule())
        .onTapGesture {
            // Click on the pill = toggle recording (same as a hotkey tap).
            switch state.phase {
            case .recording: state.finishRecording()
            case .processing: break
            default: state.startRecording()
            }
        }
    }

    /// Elegant, subtle warm rim while recording: orange-red → red-pink gradient stroke
    /// with a softly breathing outer glow.
    private var recordingGlow: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(colors: [
                    Color(red: 1.00, green: 0.45, blue: 0.25),
                    Color(red: 0.96, green: 0.22, blue: 0.44),
                ], startPoint: .leading, endPoint: .trailing),
                lineWidth: 1.8)
            .shadow(color: Color(red: 1.0, green: 0.33, blue: 0.33)
                        .opacity(glowPulse ? 0.75 : 0.35),
                    radius: glowPulse ? 8 : 4)
            .onAppear {
                glowPulse = false
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levelHistory.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5,
                           height: max(3, CGFloat(levelHistory[i]) * 26))
            }
        }
        .animation(.linear(duration: 0.05), value: levelHistory)
    }

    // MARK: - Hover panel

    private var hoverPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode switcher
            HStack(spacing: 4) {
                ForEach(state.modes) { mode in
                    Button {
                        state.selectedModeID = mode.id
                    } label: {
                        Text(mode.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                state.selectedModeID == mode.id
                                    ? AnyShapeStyle(.white.opacity(0.9))
                                    : AnyShapeStyle(.white.opacity(0.15)),
                                in: Capsule())
                            .foregroundStyle(
                                state.selectedModeID == mode.id ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }
            }

            if case .recording = state.phase {
                HStack(spacing: 6) {
                    Button(L("Done")) { state.finishRecording() }
                    Button(L("Cancel")) { state.cancelRecording() }
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
            } else if let last = state.history.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text(last.finalText)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .foregroundStyle(.white)
                    Button {
                        state.copyLastResult()
                    } label: {
                        Label(L("Copy"), systemImage: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 320)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
    }
}
