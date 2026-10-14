import AppKit
import PostDataKit
import SwiftUI

enum CodeLanguage {
    case plain, json
}

/// A monospaced text view backed by `NSTextView`: JSON highlighting, `{{variable}}` highlighting,
/// the system find bar (⌘F), undo, and optional line wrapping.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var language: CodeLanguage = .plain
    var wrapsLines = true
    var highlightsVariables = false
    var fontSize: CGFloat = 12

    /// Highlighting very large documents makes typing and scrolling sluggish.
    static let highlightLimit = 2_000_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .textBackgroundColor
        context.coordinator.configure(textView, in: scrollView, initial: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.configure(textView, in: scrollView, initial: false)
    }

    /// AppKit can keep a removed text view (and its find-bar machinery) alive for a while after
    /// SwiftUI drops it; empty the storage now so the text, highlighting and layout are freed immediately.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelPendingHighlight()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.delegate = nil
        textView.textStorage?.setAttributedString(NSAttributedString())
        textView.undoManager?.removeAllActions(withTarget: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: CodeTextView
        private var appliedFontSize: CGFloat = 0
        private var appliedWrap: Bool?
        private var appliedLanguage: CodeLanguage?
        /// The text last pushed to or read from the view. Comparing against this is O(1) when SwiftUI
        /// passes the same string again, whereas reading `textView.string` copies the whole document.
        private var appliedText: String?
        private var highlightTask: Task<Void, Never>?

        init(_ parent: CodeTextView) {
            self.parent = parent
        }

        var font: NSFont { .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular) }

        func cancelPendingHighlight() {
            highlightTask?.cancel()
            highlightTask = nil
        }

        func configure(_ textView: NSTextView, in scrollView: NSScrollView, initial: Bool) {
            textView.isEditable = parent.isEditable
            textView.isSelectable = true

            if appliedWrap != parent.wrapsLines {
                appliedWrap = parent.wrapsLines
                applyWrapping(textView, scrollView: scrollView)
            }

            var needsHighlight = initial
            if appliedFontSize != parent.fontSize {
                appliedFontSize = parent.fontSize
                textView.font = font
                textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
                needsHighlight = true
            }
            if appliedLanguage != parent.language {
                appliedLanguage = parent.language
                needsHighlight = true
            }
            if appliedText != parent.text {
                appliedText = parent.text
                let selection = textView.selectedRanges
                textView.string = parent.text
                let length = (parent.text as NSString).length
                textView.selectedRanges = selection.map { value in
                    let range = value.rangeValue
                    let location = min(range.location, length)
                    return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
                }
                needsHighlight = true
            }
            if needsHighlight { highlight(textView) }
        }

        private func applyWrapping(_ textView: NSTextView, scrollView: NSScrollView) {
            guard let container = textView.textContainer else { return }
            if parent.wrapsLines {
                scrollView.hasHorizontalScroller = false
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
                container.widthTracksTextView = true
                container.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
                textView.frame.size.width = scrollView.contentSize.width
            } else {
                scrollView.hasHorizontalScroller = true
                textView.isHorizontallyResizable = true
                textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
                container.widthTracksTextView = false
                container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let text = textView.string
            appliedText = text
            parent.text = text
            // Re-highlight right away for small documents, debounced for large ones.
            if textView.string.utf16.count < 100_000 {
                highlight(textView)
            } else {
                highlightTask?.cancel()
                highlightTask = Task { [weak self, weak textView] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled, let self, let textView else { return }
                    self.highlight(textView)
                }
            }
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let length = storage.length
            let full = NSRange(location: 0, length: length)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor], range: full)
            if length <= CodeTextView.highlightLimit {
                let text = storage.string
                if parent.language == .json {
                    for token in JSONTokenizer.tokenize(text) {
                        storage.addAttribute(.foregroundColor, value: SyntaxColors.color(for: token.kind), range: NSRange(location: token.location, length: token.length))
                    }
                }
                if parent.highlightsVariables {
                    for token in JSONTokenizer.variableTokens(in: text) {
                        storage.addAttribute(.foregroundColor, value: SyntaxColors.variable, range: NSRange(location: token.location, length: token.length))
                    }
                }
            }
            storage.endEditing()
        }
    }
}

enum SyntaxColors {
    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    static let key = dynamic(light: 0x0451A5, dark: 0x9CDCFE)
    static let string = dynamic(light: 0xA31515, dark: 0xCE9178)
    static let number = dynamic(light: 0x098658, dark: 0xB5CEA8)
    static let keyword = dynamic(light: 0x0000FF, dark: 0x569CD6)
    static let variable = dynamic(light: 0xC2410C, dark: 0xFB923C)

    static func color(for kind: SyntaxTokenKind) -> NSColor {
        switch kind {
        case .key: key
        case .string: string
        case .number: number
        case .keyword: keyword
        case .punctuation: .secondaryLabelColor
        case .variable: variable
        }
    }
}
