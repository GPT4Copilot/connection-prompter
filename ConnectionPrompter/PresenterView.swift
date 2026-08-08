import SwiftUI

struct PresenterView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    private var state: AppState { coordinator.state }
    private var style: EffectivePrompterStyle { state.preferences.effectiveStyle }
    private var backgroundStyle: PresenterBackgroundStyle {
        PresenterBackgroundStyle(
            transparency: style.backgroundTransparency,
            reduceTransparency: reduceTransparency,
            blurEnabled: state.preferences.blurEnabled
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            background

            pageContent
                .padding(.horizontal, 34)
                .padding(.vertical, 20)

            if controlsVisible && !state.preferences.clickThrough {
                controls
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    .white.opacity(0.14 * backgroundStyle.chromeOpacity),
                    lineWidth: 1
                )
        }
        .shadow(
            color: .black.opacity(0.24 * backgroundStyle.chromeOpacity),
            radius: 22,
            y: 10
        )
        .onHover { hovering in
            if hovering {
                showControls()
            } else {
                scheduleControlsHide()
            }
        }
        .onAppear { scheduleControlsHide() }
        .animation(.easeOut(duration: 0.18), value: controlsVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主持浮窗")
    }

    private var background: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(backgroundStyle.materialOpacity)
            Color.black.opacity(backgroundStyle.blackFillOpacity)
        }
    }

    private var pageContent: some View {
        Group {
            if let page = state.currentPrompterPage {
                VStack(
                    alignment: state.preferences.alignment == .center ? .center : .leading,
                    spacing: 2
                ) {
                    ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(lineFont(for: line.role))
                            .foregroundStyle(lineColor(for: line.role))
                            .frame(maxWidth: .infinity, alignment: textAlignment)
                            .lineLimit(1)
                            .minimumScaleFactor(0.64)
                            .accessibilityLabel(line.text)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 22))
                    Text("文稿还是空的")
                        .font(.system(size: 17, weight: .semibold))
                    Text("返回编辑器，粘贴你的会议讲稿")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            controlButton("上一页", systemImage: "chevron.up", action: coordinator.previousPage)
            controlButton("下一页", systemImage: "chevron.down", action: coordinator.nextPage)
            separator
            controlButton(
                "People View",
                systemImage: "person.2.fill",
                isActive: state.preferences.peopleView,
                action: coordinator.togglePeopleView
            )
            controlButton("减小字号", systemImage: "textformat.size.smaller") {
                coordinator.adjustFontSize(by: -2)
            }
            controlButton("增大字号", systemImage: "textformat.size.larger") {
                coordinator.adjustFontSize(by: 2)
            }
            controlButton("降低透明度", systemImage: "circle.fill") {
                coordinator.adjustTransparency(by: -0.05)
            }
            controlButton("提高透明度", systemImage: "circle.lefthalf.filled") {
                coordinator.adjustTransparency(by: 0.05)
            }
            separator
            controlButton(
                "鼠标穿透",
                systemImage: "cursorarrow.slash",
                isActive: state.preferences.clickThrough,
                action: coordinator.toggleClickThrough
            )
            controlButton("返回编辑器", systemImage: "rectangle.portrait.and.arrow.right") {
                coordinator.returnToEditor()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private var separator: some View {
        Divider().frame(height: 17).padding(.horizontal, 2)
    }

    private func controlButton(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(isActive ? Color.accentColor.opacity(0.28) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(title)
        .accessibilityLabel(title)
    }

    private func lineFont(for role: PrompterLineRole) -> Font {
        let size = state.preferences.fontSize
        return switch role {
        case .cue: Font.system(size: min(size * 0.78, 28), weight: .semibold, design: .rounded)
        case .current: Font.system(size: size, weight: .semibold, design: .rounded)
        case .previous, .next: Font.system(size: size * 0.9, weight: .medium, design: .rounded)
        }
    }

    private func lineColor(for role: PrompterLineRole) -> Color {
        return switch role {
        case .current: Color.white
        case .cue: Color(red: 0.64, green: 0.82, blue: 1)
        case .previous, .next: Color.white.opacity(0.42)
        }
    }

    private var textAlignment: Alignment {
        state.preferences.alignment == .center ? .center : .leading
    }

    private func showControls() {
        hideControlsTask?.cancel()
        controlsVisible = true
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }
}
