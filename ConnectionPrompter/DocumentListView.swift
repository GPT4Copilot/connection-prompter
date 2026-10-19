import SwiftUI

enum DocumentDeletionPrompt {
    private static let maximumDocumentNameLength = 36

    static func title(for rawTitle: String) -> String {
        let normalizedTitle = rawTitle
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let documentName = normalizedTitle.isEmpty ? "未命名文稿" : normalizedTitle
        let visibleName = documentName.prefix(maximumDocumentNameLength)
        let truncationMark = documentName.count > maximumDocumentNameLength ? "…" : ""
        return "删除“\(visibleName)\(truncationMark)”？"
    }
}

struct DocumentListView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var deleteConfirmationPresented = false

    private var state: AppState { coordinator.state }
    private var groups: [DocumentDayGroup] {
        DocumentGrouping.group(state.visibleDocuments)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            if groups.isEmpty {
                ContentUnavailableView(
                    "没有找到文稿",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("试试其他标题或正文关键词")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                documentList
            }

            Divider()
            bottomBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
        .confirmationDialog(
            DocumentDeletionPrompt.title(for: state.document.title),
            isPresented: $deleteConfirmationPresented
        ) {
            Button("删除文稿", role: .destructive) {
                state.deleteSelectedDocument()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该文稿将从这台 Mac 上删除，此操作无法撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("文稿")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("\(state.library.documents.count) 个文稿")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                state.createDocument()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("新建文稿")
            .accessibilityLabel("新建文稿")
            .accessibilityIdentifier("新建文稿")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        TextField("搜索文稿…", text: searchBinding)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("搜索文稿")
            .accessibilityIdentifier("搜索文稿")
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
    }

    private var documentList: some View {
        List(selection: selectionBinding) {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.documents) { document in
                        DocumentListRow(document: document)
                            .tag(document.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityLabel("文稿列表")
        .accessibilityIdentifier("文稿列表")
    }

    private var bottomBar: some View {
        HStack {
            Button {
                state.createDocument()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            .help("新建文稿")
            .accessibilityLabel("新建文稿")

            Spacer()

            Button {
                deleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除文稿")
            .accessibilityLabel("删除文稿")
            .accessibilityIdentifier("删除文稿")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { state.searchQuery },
            set: { state.searchQuery = $0 }
        )
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { state.library.selectedDocumentID },
            set: { id in
                if let id {
                    state.selectDocument(id)
                }
            }
        )
    }
}

private struct DocumentListRow: View {
    let document: ScriptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title.isEmpty ? "未命名文稿" : document.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 7) {
                Text(document.updatedAt, format: .dateTime.hour().minute())
                    .foregroundStyle(.primary)
                Text(preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var preview: String {
        let normalized = document.content
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return normalized.isEmpty ? "暂无内容" : normalized
    }
}
