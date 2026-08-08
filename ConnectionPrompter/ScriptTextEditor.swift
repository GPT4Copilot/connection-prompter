import AppKit
import SwiftUI

struct CueInsertionRequest: Equatable {
    let id = UUID()
    let cue: CueKind
}

struct ScriptTextEditor: NSViewRepresentable {
    @Binding var text: String
    var insertionRequest: CueInsertionRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 12)
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.string = text
        textView.setAccessibilityIdentifier("文稿正文")
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text, !context.coordinator.isApplyingTextChange {
            textView.string = text
        }

        guard let request = insertionRequest,
              request.id != context.coordinator.lastInsertionID else { return }

        let result = CueTextInsertion.inserting(
            request.cue,
            into: textView.string,
            selectedRange: textView.selectedRange()
        )
        context.coordinator.lastInsertionID = request.id
        context.coordinator.isApplyingTextChange = true
        textView.string = result.text
        textView.setSelectedRange(NSRange(location: result.selectionLocation, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        context.coordinator.parent.text = result.text
        context.coordinator.isApplyingTextChange = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextEditor
        var lastInsertionID: UUID?
        var isApplyingTextChange = false

        init(parent: ScriptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingTextChange,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
