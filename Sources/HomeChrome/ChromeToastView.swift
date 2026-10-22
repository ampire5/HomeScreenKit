import AppKit

/// A short message on glass: fades in, stays for the given time, fades out. Takes no clicks.
@MainActor public final class ChromeToastView: NSView {
    private let glass: ChromeGlass
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?
    /// True from `show` until `hide` (or the timeout): "requested visible", not "fade finished".
    public private(set) var isShowing = false

    public init(style: ChromeGlass.Style) {
        glass = ChromeGlass(style: style, cornerRadius: Chrome.Radius.card)
        super.init(frame: .zero)
        label.font = Chrome.Text.digits(.label)
        label.textColor = switch style {
        case .overMedia: Chrome.Palette.overMedia.text
        case .window: Chrome.Palette.window.label
        }
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: Chrome.Space.s),
            label.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -Chrome.Space.s),
            label.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: Chrome.Space.l),
            label.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -Chrome.Space.l),
        ])
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var intrinsicContentSize: NSSize {
        let text = label.intrinsicContentSize
        return NSSize(width: text.width + 2 * Chrome.Space.l, height: text.height + 2 * Chrome.Space.s)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public func show(_ text: String, for seconds: TimeInterval) {
        hideTask?.cancel()
        label.stringValue = text
        isShowing = true
        isHidden = false
        invalidateIntrinsicContentSize()
        fade(to: 1, duration: Chrome.Motion.duration(Chrome.Motion.show))
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    public func hide() {
        guard isShowing else { return }
        hideTask?.cancel()
        hideTask = nil
        isShowing = false
        fade(to: 0, duration: Chrome.Motion.duration(Chrome.Motion.hide)) { [weak self] in
            guard let self, !self.isShowing else { return }
            self.isHidden = true
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        if duration == 0 {
            alphaValue = alpha
            completion?()
        } else {
            NSAnimationContext.runAnimationGroup({ c in
                c.duration = duration
                animator().alphaValue = alpha
            }, completionHandler: { MainActor.assumeIsolated { completion?() } })
        }
    }
}
