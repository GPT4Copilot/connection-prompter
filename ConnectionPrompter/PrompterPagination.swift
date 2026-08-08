import AppKit
import Foundation

struct PrompterLayout: Equatable, Sendable {
    var width: Double
    var fontSize: Double
    var lineHeight: Double
    var maximumLines: Int
}

enum PrompterLineRole: Equatable, Sendable {
    case previous
    case current
    case next
    case cue
}

struct PrompterLine: Equatable, Sendable {
    var text: String
    var role: PrompterLineRole
}

struct PrompterPage: Equatable, Sendable {
    var blockIndex: Int
    var pageInBlock: Int
    var lines: [PrompterLine]
}

protocol TextLineBreaking: Sendable {
    func lines(for text: String, layout: PrompterLayout) -> [String]
}

struct TextKitLineBreaker: TextLineBreaking {
    func lines(for text: String, layout: PrompterLayout) -> [String] {
        guard !text.isEmpty else { return [] }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = layout.lineHeight
        paragraphStyle.lineBreakMode = .byWordWrapping

        let textStorage = NSTextStorage(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: layout.fontSize),
                .paragraphStyle: paragraphStyle
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: max(layout.width, 1), height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var result: [String] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, _, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let line = (text as NSString)
                .substring(with: characterRange)
                .trimmingCharacters(in: .newlines)
            if !line.isEmpty {
                result.append(line)
            }
        }
        return result
    }
}

protocol PageComposing: Sendable {
    func compose(blocks: [ScriptBlock], layout: PrompterLayout) -> [PrompterPage]
}

struct PageComposer<LineBreaker: TextLineBreaking>: PageComposing {
    let lineBreaker: LineBreaker

    func compose(blocks: [ScriptBlock], layout: PrompterLayout) -> [PrompterPage] {
        let maximumLines = max(1, layout.maximumLines)
        let wrappedLines = blocks.map { block -> [String] in
            switch block {
            case let .text(text):
                lineBreaker.lines(for: text, layout: layout)
            case let .cue(cue):
                [cue.displayLabel]
            }
        }

        var pages: [PrompterPage] = []
        for (blockIndex, block) in blocks.enumerated() {
            switch block {
            case let .cue(cue):
                pages.append(
                    PrompterPage(
                        blockIndex: blockIndex,
                        pageInBlock: 0,
                        lines: [PrompterLine(text: cue.displayLabel, role: .cue)]
                    )
                )

            case .text:
                let lines = wrappedLines[blockIndex]
                guard !lines.isEmpty else { continue }

                for (pageInBlock, start) in stride(from: 0, to: lines.count, by: maximumLines).enumerated() {
                    let end = min(start + maximumLines, lines.count)
                    var pageLines = lines[start..<end].map {
                        PrompterLine(text: $0, role: .current)
                    }

                    if pageInBlock == 0,
                       pageLines.count < maximumLines,
                       let previous = contextLine(before: blockIndex, blocks: blocks, wrappedLines: wrappedLines) {
                        pageLines.insert(PrompterLine(text: previous, role: .previous), at: 0)
                    }

                    if end == lines.count,
                       pageLines.count < maximumLines,
                       let next = contextLine(after: blockIndex, blocks: blocks, wrappedLines: wrappedLines) {
                        pageLines.append(PrompterLine(text: next, role: .next))
                    }

                    pages.append(
                        PrompterPage(
                            blockIndex: blockIndex,
                            pageInBlock: pageInBlock,
                            lines: pageLines
                        )
                    )
                }
            }
        }
        return pages
    }

    private func contextLine(
        before index: Int,
        blocks: [ScriptBlock],
        wrappedLines: [[String]]
    ) -> String? {
        guard index > 0, case .text = blocks[index - 1] else { return nil }
        return wrappedLines[index - 1].last
    }

    private func contextLine(
        after index: Int,
        blocks: [ScriptBlock],
        wrappedLines: [[String]]
    ) -> String? {
        guard index + 1 < blocks.count, case .text = blocks[index + 1] else { return nil }
        return wrappedLines[index + 1].first
    }
}

enum PageNavigation {
    static func previous(from current: Int, pageCount: Int) -> Int {
        clamp(current - 1, pageCount: pageCount)
    }

    static func next(from current: Int, pageCount: Int) -> Int {
        clamp(current + 1, pageCount: pageCount)
    }

    static func clamp(_ index: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(index, 0), pageCount - 1)
    }
}
