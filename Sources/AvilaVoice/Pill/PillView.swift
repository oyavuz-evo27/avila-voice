import SwiftUI

/// The pill: a tiny bar at rest, grows while recording and shows a live waveform.
/// Hovering opens a compact panel with mode switching and the last transcript.
struct PillView: View {
    @EnvironmentObject var state: AppState
    @State private var hovering = false
    @State private var levelHistory: [Float] = Array(repeating: 0, count: 24)

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if hovering {
                hoverPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            pill
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self.hovering = hovering
            }
        }
        .onChange(of: state.audioLevel) { _, level in
            levelHistory.removeFirst()
            levelHistory.append(level)
        }
    }

    // MARK: - The pill itself

    private var pill: some View {
        Group {
            switch state.phase {
            case .recording:
                waveform
                    .frame(width: 130, height: 26)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60, height: 18)
            case .result(let inserted):
                Image(systemName: inserted ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 60, height: 18)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.yellow)
                    .frame(width: 60, height: 18)
            case .idle:
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 34, height: 4)
                    .frame(width: 60, height: 10)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.phase)
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levelHistory.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5,
                           height: max(3, CGFloat(levelHistory[i]) * 22))
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
