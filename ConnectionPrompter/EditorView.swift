import SwiftUI

struct EditorView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var insertionRequest: CueInsertionRequest?
    @State private var settingsPresented = false

    private var state: AppState { coordinator.state }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider().opacity(0.55)

            if let message = state.bannerMessage {
                banner(message)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }

            HStack {
                Spacer(minLength: 44)
                VStack(alignment: .leading, spacing: 0) {
                    TextField("文稿标题", text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("文稿标题")
                        .padding(.top, 42)
                        .padding(.bottom, 22)

                    ZStack(alignment: .topLeading) {
                        ScriptTextEditor(
                            text: contentBinding,
                            insertionRequest: insertionRequest
                        )

                        if state.document.content.isEmpty {
                            Text("粘贴或输入你的会议讲稿…\n\n用空行分段，主持时会自动按 2–4 行分页。")
                                .font(.system(size: 17))
                                .foregroundStyle(.tertiary)
                                .lineSpacing(7)
                                .padding(.leading, 8)
                                .padding(.top, 14)
                                .allowsHitTesting(false)
                        }
                    }

                    if state.longParagraphCount > 0 {
                        Label(
                            "有 \(state.longParagraphCount) 个段落较长，建议用空行拆分，主持时更易阅读。",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.top, 10)
                    }

                    HStack(spacing: 14) {
                        Label("自动保存", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(state.characterCount) 字符")
                        Text("\(state.segmentCount) 段")
                        Text("\(state.pages.count) 页")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 15)
                }
                .frame(maxWidth: 760)
                Spacer(minLength: 44)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 820, minHeight: 600)
        .onAppear { coordinator.connectIfNeeded() }
    }

    private var editorToolbar: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.document")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Connection Prompter")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Menu {
                ForEach(CueKind.allCases, id: \.self) { cue in
                    Button(cue.menuTitle) {
                        insertionRequest = CueInsertionRequest(cue: cue)
                    }
                }
            } label: {
                Label("插入提示", systemImage: "sparkles.rectangle.stack")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("插入提示")

            toolbarDivider

            Picker("对齐", selection: alignmentBinding) {
                Image(systemName: "text.aligncenter").tag(TextAlignmentSetting.center)
                Image(systemName: "text.alignleft").tag(TextAlignmentSetting.left)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 76)

            Button {
                settingsPresented.toggle()
            } label: {
                Label("显示设置", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("显示设置")
            .popover(isPresented: $settingsPresented, arrowEdge: .bottom) {
                PrompterSettingsView(coordinator: coordinator)
            }

            toolbarDivider

            Button {
                coordinator.showPresenter()
            } label: {
                Label("进入主持", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityIdentifier("进入主持")
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(.bar)
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 22).padding(.horizontal, 3)
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button {
                state.dismissBanner()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { state.document.title },
            set: { value in state.updateTitle(value) }
        )
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { state.document.content },
            set: { value in state.updateContent(value) }
        )
    }

    private var alignmentBinding: Binding<TextAlignmentSetting> {
        Binding(
            get: { state.preferences.alignment },
            set: { value in coordinator.updatePreferences { $0.alignment = value } }
        )
    }
}

private struct PrompterSettingsView: View {
    @Bindable var coordinator: AppCoordinator

    private var state: AppState { coordinator.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("主持显示")
                .font(.system(size: 16, weight: .semibold))

            settingRow("字号", value: "\(Int(state.preferences.fontSize)) pt") {
                Slider(value: fontSizeBinding, in: 24...48, step: 2)
                    .accessibilityLabel("字号")
            }

            settingRow("每页行数", value: "\(state.preferences.maximumLines) 行") {
                Slider(value: maximumLinesBinding, in: 2...4, step: 1)
                    .accessibilityLabel("每页行数")
            }

            settingRow("背景透明度", value: "\(Int(state.preferences.backgroundTransparency * 100))%") {
                Slider(value: transparencyBinding, in: 0...1, step: 0.01)
                    .accessibilityLabel("背景透明度")
            }

            Picker("行距", selection: lineDensityBinding) {
                ForEach(LineDensity.allCases, id: \.self) { density in
                    Text(density.label).tag(density)
                }
            }
            .pickerStyle(.segmented)

            Toggle("背景模糊", isOn: blurBinding)
            Toggle("始终置顶", isOn: alwaysOnTopBinding)
        }
        .padding(20)
        .frame(width: 300)
    }

    private func settingRow<Content: View>(
        _ title: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5, weight: .medium))
            content()
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(get: { state.preferences.fontSize }, set: { value in
            coordinator.updatePreferences { $0.fontSize = value }
        })
    }

    private var maximumLinesBinding: Binding<Double> {
        Binding(get: { Double(state.preferences.maximumLines) }, set: { value in
            coordinator.updatePreferences { $0.maximumLines = Int(value) }
        })
    }

    private var transparencyBinding: Binding<Double> {
        Binding(get: { state.preferences.backgroundTransparency }, set: { value in
            coordinator.updatePreferences { $0.backgroundTransparency = value }
        })
    }

    private var lineDensityBinding: Binding<LineDensity> {
        Binding(get: { state.preferences.lineDensity }, set: { value in
            coordinator.updatePreferences { $0.lineDensity = value }
        })
    }

    private var blurBinding: Binding<Bool> {
        Binding(get: { state.preferences.blurEnabled }, set: { value in
            coordinator.updatePreferences { $0.blurEnabled = value }
        })
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(get: { state.preferences.alwaysOnTop }, set: { value in
            coordinator.updatePreferences { $0.alwaysOnTop = value }
        })
    }
}
