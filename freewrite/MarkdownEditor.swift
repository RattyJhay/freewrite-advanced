//
//  MarkdownEditor.swift
//  Considered
//
//  A quiet Markdown editor in the spirit of iA Writer: the text stays plain,
//  syntax is styled in place (markers softly dimmed), and two optional modes,
//  Focus (dim everything but the current paragraph) and Typewriter
//  (keep the current line at the centre of the window), help you stay with one thought.
//

import SwiftUI
import AppKit

struct EditorStyle: Equatable {
    var typeface: Typeface
    var fontSize: CGFloat
    var colorScheme: ColorScheme
    var focusMode: Bool
    var typewriterMode: Bool
    var spellCheck: Bool
}

/// Lets SwiftUI ask the text view to do things (insert a section, take focus).
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Adds a Markdown section heading at the end of the piece and puts the caret under it.
    func appendSection(_ heading: String) {
        guard let textView else { return }
        let current = textView.string
        let length = (current as NSString).length
        var insertion = ""
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if current.hasSuffix("\n\n") {
                insertion = ""
            } else if current.hasSuffix("\n") {
                insertion = "\n"
            } else {
                insertion = "\n\n"
            }
        }
        insertion += "## \(heading)\n\n"
        let end = NSRange(location: length, length: 0)
        textView.setSelectedRange(end)
        textView.insertText(insertion, replacementRange: end)
        textView.scrollRangeToVisible(textView.selectedRange())
        focus()
    }

    func moveCaretToEnd() {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

/// Wiki links between pieces use this scheme: considered-piece:<title>.
enum PieceLink {
    static let scheme = "considered-piece"

    static func url(forTitle title: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(scheme):\(encoded)")
    }

    static func title(from link: Any) -> String? {
        let url: URL?
        if let linkURL = link as? URL {
            url = linkURL
        } else if let string = link as? String {
            url = URL(string: string)
        } else {
            url = nil
        }
        guard let url, url.scheme == scheme else { return nil }
        let raw = url.absoluteString.dropFirst(scheme.count + 1)
        return String(raw).removingPercentEncoding
    }
}

final class WritingTextView: NSTextView {
    var columnWidth: CGFloat = 650 {
        didSet { updateInsets() }
    }
    var typewriterMode = false {
        didSet { updateInsets() }
    }
    var verticalInset: CGFloat = 56 {
        didSet { updateInsets() }
    }
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }
    var placeholderAttributes: [NSAttributedString.Key: Any] = [:] {
        didSet { needsDisplay = true }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    func updateInsets() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        let horizontal = max(28, ((width - columnWidth) / 2).rounded(.down))
        var vertical = verticalInset
        if typewriterMode, let visibleHeight = enclosingScrollView?.contentSize.height {
            vertical = max(verticalInset, (visibleHeight / 2).rounded(.down))
        }
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }

    override func didChangeText() {
        super.didChangeText()
        if string.isEmpty || (string as NSString).length < 2 {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let origin = NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height)
        (placeholderString as NSString).draw(at: origin, withAttributes: placeholderAttributes)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var style: EditorStyle
    var placeholder: String
    var controller: EditorController
    var onOpenPiece: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 5
        layoutManager.addTextContainer(textContainer)
        coordinator.textStorage = textStorage

        let textView = WritingTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
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
        textView.isGrammarCheckingEnabled = false
        textView.delegate = coordinator
        textStorage.delegate = coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.contentView.postsFrameChangedNotifications = true

        coordinator.textView = textView
        coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak textView, weak coordinator] _ in
            textView?.updateInsets()
            if let textView, let coordinator, coordinator.parent.style.typewriterMode {
                coordinator.centerCaret(in: textView, animated: false)
            }
        }
        controller.textView = textView

        coordinator.apply(style: style, to: textView, force: true)
        textView.string = text
        coordinator.restyleAll()
        textView.placeholderString = placeholder
        DispatchQueue.main.async {
            textView.updateInsets()
            textView.window?.makeFirstResponder(textView)
            coordinator.parent.controller.moveCaretToEnd()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        controller.textView = textView

        let styleChanged = coordinator.apply(style: style, to: textView, force: false)

        if textView.string != text {
            // A different piece was opened (or the file changed on disk).
            coordinator.isReplacingText = true
            textView.string = text
            coordinator.isReplacingText = false
            coordinator.restyleAll()
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: length, length: 0))
            textView.undoManager?.removeAllActions()
            textView.scrollRangeToVisible(textView.selectedRange())
            if style.typewriterMode {
                coordinator.centerCaret(in: textView, animated: false)
            }
        } else if styleChanged {
            coordinator.restyleAll()
            if style.typewriterMode {
                coordinator.centerCaret(in: textView, animated: false)
            }
        }

        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.frameObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.frameObserver = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        weak var textView: WritingTextView?
        var textStorage: NSTextStorage?
        var frameObserver: NSObjectProtocol?
        var isReplacingText = false
        private var appliedStyle: EditorStyle?
        private var focusParagraph: NSRange?
        private var styler = MarkdownStyler(style: EditorStyle(typeface: .mono, fontSize: 18, colorScheme: .light, focusMode: false, typewriterMode: false, spellCheck: false))

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        /// Returns true when the visual style changed and the text needs restyling.
        @discardableResult
        func apply(style: EditorStyle, to textView: WritingTextView, force: Bool) -> Bool {
            guard force || appliedStyle != style else { return false }
            appliedStyle = style
            styler = MarkdownStyler(style: style)
            let palette = Palette.forScheme(style.colorScheme)

            textView.font = styler.baseFont
            textView.typingAttributes = styler.baseAttributes
            textView.insertionPointColor = palette.accent
            textView.selectedTextAttributes = [.backgroundColor: palette.selection]
            textView.linkTextAttributes = [
                .foregroundColor: palette.accent,
                .cursor: NSCursor.pointingHand
            ]
            textView.isContinuousSpellCheckingEnabled = style.spellCheck
            textView.columnWidth = style.typeface.columnWidth(fontSize: style.fontSize)
            textView.typewriterMode = style.typewriterMode
            textView.placeholderAttributes = [
                .font: styler.baseFont,
                .foregroundColor: palette.faintInk
            ]
            textView.updateInsets()
            return true
        }

        func restyleAll() {
            guard let textStorage else { return }
            focusParagraph = currentParagraphRange()
            let full = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            styler.apply(to: textStorage, in: full, focus: appliedStyle?.focusMode == true ? focusParagraph : nil)
            textStorage.endEditing()
            textView?.typingAttributes = styler.baseAttributes
        }

        private func currentParagraphRange() -> NSRange? {
            guard let textView, let textStorage else { return nil }
            let string = textStorage.string as NSString
            let location = min(textView.selectedRange().location, string.length)
            return string.paragraphRange(for: NSRange(location: location, length: 0))
        }

        // MARK: NSTextStorageDelegate

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            let string = textStorage.string as NSString
            let safeRange = NSIntersectionRange(editedRange, NSRange(location: 0, length: string.length))
            let paragraph = string.paragraphRange(for: safeRange)
            let focus: NSRange? = appliedStyle?.focusMode == true ? paragraph : nil
            if appliedStyle?.focusMode == true {
                focusParagraph = paragraph
            }
            styler.apply(to: textStorage, in: paragraph, focus: focus)
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView, !isReplacingText else { return }
            parent.text = textView.string
            textView.typingAttributes = styler.baseAttributes
            if appliedStyle?.typewriterMode == true {
                centerCaret(in: textView, animated: false)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !isReplacingText else { return }
            if appliedStyle?.focusMode == true, let textStorage {
                let newParagraph = currentParagraphRange()
                if newParagraph != focusParagraph {
                    let length = textStorage.length
                    var ranges: [NSRange] = []
                    if let old = focusParagraph { ranges.append(NSIntersectionRange(old, NSRange(location: 0, length: length))) }
                    if let new = newParagraph { ranges.append(new) }
                    focusParagraph = newParagraph
                    textStorage.beginEditing()
                    for range in ranges where range.length > 0 {
                        let paragraph = (textStorage.string as NSString).paragraphRange(for: range)
                        styler.apply(to: textStorage, in: paragraph, focus: newParagraph)
                    }
                    textStorage.endEditing()
                    textView.typingAttributes = styler.baseAttributes
                }
            }
            if appliedStyle?.typewriterMode == true {
                centerCaret(in: textView, animated: true)
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let title = PieceLink.title(from: link) {
                parent.onOpenPiece(title)
                return true
            }
            return false
        }

        /// Keeps the caret's line at the vertical centre of the window.
        func centerCaret(in textView: NSTextView, animated: Bool) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }
            layoutManager.ensureLayout(for: textContainer)

            let length = (textView.string as NSString).length
            let caret = textView.selectedRange().location
            var lineRect: NSRect
            if length == 0 || (caret >= length && !layoutManager.extraLineFragmentRect.isEmpty) {
                lineRect = layoutManager.extraLineFragmentRect
            } else {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(caret, length - 1))
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }
            lineRect.origin.y += textView.textContainerOrigin.y

            let clipView = scrollView.contentView
            let visibleHeight = clipView.bounds.height
            let maxY = max(0, textView.frame.height - visibleHeight)
            let targetY = min(max(0, lineRect.midY - visibleHeight / 2), maxY)
            guard abs(clipView.bounds.origin.y - targetY) > 0.5 else { return }

            let target = NSPoint(x: clipView.bounds.origin.x, y: targetY)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    clipView.animator().setBoundsOrigin(target)
                }
            } else {
                clipView.setBoundsOrigin(target)
            }
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

/// Styles Markdown in place. Every pattern is line-local, so restyling one paragraph is always correct.
struct MarkdownStyler {
    let style: EditorStyle
    let palette: Palette
    let baseFont: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    let boldItalicFont: NSFont
    let codeFont: NSFont
    let paragraphStyle: NSParagraphStyle
    let baseAttributes: [NSAttributedString.Key: Any]

    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+(.*)$", options: [.anchorsMatchLines])
    private static let blockquote = try! NSRegularExpression(pattern: "^(>[ \\t]?)(.*)$", options: [.anchorsMatchLines])
    private static let listMarker = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|\\d+[.)])([ \\t]+)", options: [.anchorsMatchLines])
    private static let taskBox = try! NSRegularExpression(pattern: "^([ \\t]*[-*+][ \\t]+)(\\[[ xX]\\])", options: [.anchorsMatchLines])
    private static let rule = try! NSRegularExpression(pattern: "^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$", options: [.anchorsMatchLines])
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", options: [])
    private static let italicStar = try! NSRegularExpression(pattern: "(?<![\\*\\w])\\*(?![\\*\\s])(.+?)(?<![\\*\\s])\\*(?![\\*\\w])", options: [])
    private static let italicUnderscore = try! NSRegularExpression(pattern: "(?<![_\\w])_(?![_\\s])(.+?)(?<![_\\s])_(?![_\\w])", options: [])
    private static let code = try! NSRegularExpression(pattern: "`[^`\\n]+`", options: [])
    private static let link = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)", options: [])
    private static let wikiLink = try! NSRegularExpression(pattern: "\\[\\[([^\\[\\]\\n]+)\\]\\]", options: [])
    private static let highlight = try! NSRegularExpression(pattern: "==(?=\\S)(.+?)(?<=\\S)==", options: [])

    init(style: EditorStyle) {
        self.style = style
        palette = Palette.forScheme(style.colorScheme)
        let fontManager = NSFontManager.shared
        baseFont = style.typeface.nsFont(size: style.fontSize)
        boldFont = fontManager.convert(baseFont, toHaveTrait: .boldFontMask)
        italicFont = fontManager.convert(baseFont, toHaveTrait: .italicFontMask)
        boldItalicFont = fontManager.convert(boldFont, toHaveTrait: .italicFontMask)
        codeFont = NSFont(name: Typeface.mono.postScriptName, size: style.fontSize * (style.typeface == .mono ? 1 : 0.9))
            ?? NSFont.monospacedSystemFont(ofSize: style.fontSize * 0.9, weight: .regular)

        let paragraph = NSMutableParagraphStyle()
        let naturalLineHeight = baseFont.ascender - baseFont.descender + baseFont.leading
        paragraph.lineSpacing = max(0, style.fontSize * 1.62 - naturalLineHeight)
        paragraph.paragraphSpacing = 0
        paragraphStyle = paragraph

        baseAttributes = [
            .font: baseFont,
            .foregroundColor: palette.ink,
            .paragraphStyle: paragraph
        ]
    }

    func apply(to storage: NSTextStorage, in range: NSRange, focus: NSRange?) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let string = storage.string as NSString
        storage.setAttributes(baseAttributes, range: range)

        let marker = palette.faintInk

        Self.heading.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let level = match.range(at: 1).length
            let scale: CGFloat
            if style.typeface.scalesHeadings {
                scale = level == 1 ? 1.32 : (level == 2 ? 1.16 : (level == 3 ? 1.06 : 1.0))
            } else {
                scale = 1.0
            }
            let headingFont = NSFontManager.shared.convert(boldFont, toSize: style.fontSize * scale)
            let headingParagraph = (paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            headingParagraph.paragraphSpacingBefore = style.fontSize * 0.4
            storage.addAttributes([.font: headingFont, .paragraphStyle: headingParagraph], range: match.range)
            storage.addAttribute(.foregroundColor, value: marker, range: match.range(at: 1))
        }

        Self.blockquote.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: marker, range: match.range(at: 1))
            storage.addAttributes([.foregroundColor: palette.secondaryInk, .font: italicFont], range: match.range(at: 2))
        }

        Self.listMarker.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: palette.secondaryInk, range: match.range(at: 2))
        }

        Self.taskBox.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: palette.accent, range: match.range(at: 2))
        }

        Self.rule.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: marker, range: match.range)
        }

        Self.bold.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            applyTrait(storage, bold: true, range: match.range(at: 2))
            let delimiter = match.range(at: 1).length
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: match.range.location, length: delimiter))
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: NSMaxRange(match.range) - delimiter, length: delimiter))
        }

        for regex in [Self.italicStar, Self.italicUnderscore] {
            regex.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
                guard let match else { return }
                applyTrait(storage, bold: false, range: match.range(at: 1))
                storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: match.range.location, length: 1))
                storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: NSMaxRange(match.range) - 1, length: 1))
            }
        }

        Self.highlight.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.backgroundColor, value: palette.developingStage.withAlphaComponent(0.22), range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: match.range.location, length: 2))
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: NSMaxRange(match.range) - 2, length: 2))
        }

        Self.code.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttributes([.font: codeFont, .foregroundColor: palette.secondaryInk], range: match.range)
        }

        Self.link.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: marker, range: match.range)
            storage.addAttribute(.foregroundColor, value: palette.accent, range: match.range(at: 1))
            let target = string.substring(with: match.range(at: 2))
            if let url = URL(string: target), let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme.lowercased()) {
                storage.addAttribute(.link, value: url, range: match.range(at: 1))
            }
        }

        Self.wikiLink.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let titleRange = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: marker, range: match.range)
            let title = string.substring(with: titleRange)
            if let url = PieceLink.url(forTitle: title) {
                storage.addAttribute(.link, value: url, range: titleRange)
            }
        }

        if let focus {
            dim(storage, in: range, except: focus)
        }
    }

    private func applyTrait(_ storage: NSTextStorage, bold: Bool, range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? baseFont
            let traits = NSFontManager.shared.traits(of: current)
            let font: NSFont
            if bold {
                font = traits.contains(.italicFontMask) ? NSFontManager.shared.convert(boldItalicFont, toSize: current.pointSize) : NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
            } else {
                font = traits.contains(.boldFontMask) ? NSFontManager.shared.convert(boldItalicFont, toSize: current.pointSize) : NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
            }
            storage.addAttribute(.font, value: font, range: subrange)
        }
    }

    private func dim(_ storage: NSTextStorage, in range: NSRange, except focus: NSRange) {
        let before = NSRange(location: range.location, length: max(0, min(NSMaxRange(range), focus.location) - range.location))
        let afterStart = max(range.location, NSMaxRange(focus))
        let after = NSRange(location: afterStart, length: max(0, NSMaxRange(range) - afterStart))
        for segment in [before, after] where segment.length > 0 {
            storage.addAttribute(.foregroundColor, value: palette.focusDim, range: segment)
        }
    }
}
