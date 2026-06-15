import AppKit
import Foundation
import TokenTrackerCore

private enum StatusSegment {
    case icon(NSImage)
    case text(String, NSColor)
    case separator
}

@MainActor
final class StatusItemRenderer {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var claudeIcon = loadIcon(named: "claudeTemplate@2x")
    private lazy var codexIcon = loadIcon(named: "codexTemplate@2x")
    private let sevenDayWarningColor = NSColor(red: 1.0, green: 0.54, blue: 0.56, alpha: 1.0)
    private let statusItemHorizontalPadding: CGFloat = 10

    func setMenu(_ menu: NSMenu) {
        statusItem.menu = menu
    }

    func setPlaceholder(mode: DisplayMode, labelStyle: ProviderLabelStyle) {
        setStatusTitle("AI --", mode: mode, labelStyle: labelStyle)
    }

    func setLoading(mode: DisplayMode, labelStyle: ProviderLabelStyle) {
        setStatusTitle("AI ...", mode: mode, labelStyle: labelStyle)
    }

    func update(snapshot: UsageSnapshot?, mode: DisplayMode, labelStyle: ProviderLabelStyle) {
        if let snapshot {
            let textColor = statusTextColor
            setStatusSegments(
                statusSegments(
                    snapshot: snapshot,
                    mode: mode,
                    labelStyle: labelStyle,
                    baseColor: textColor,
                    warningColor: statusWarningColor
                ),
                iconTint: textColor,
                mode: mode,
                labelStyle: labelStyle
            )
        } else {
            setStatusTitle(
                DisplayFormatter.statusTitle(snapshot: snapshot, mode: mode),
                mode: mode,
                labelStyle: labelStyle
            )
        }
    }

    private func setStatusTitle(
        _ title: String,
        mode: DisplayMode = .lowestRemaining,
        labelStyle: ProviderLabelStyle = .abbreviation
    ) {
        guard let button = statusItem.button else { return }
        let image = statusTitleImage(title, color: statusTextColor)
        setStatusImage(image, on: button, mode: mode, labelStyle: labelStyle)
    }

    private func setStatusSegments(
        _ segments: [StatusSegment],
        iconTint: NSColor,
        mode: DisplayMode,
        labelStyle: ProviderLabelStyle
    ) {
        guard let button = statusItem.button else { return }
        let image = statusTitleImage(segments: segments, iconTint: iconTint)
        setStatusImage(image, on: button, mode: mode, labelStyle: labelStyle)
    }

    private func setStatusImage(
        _ image: NSImage,
        on button: NSStatusBarButton,
        mode: DisplayMode,
        labelStyle: ProviderLabelStyle
    ) {
        let targetLength = max(
            image.size.width + statusItemHorizontalPadding,
            reservedStatusItemLength(mode: mode, labelStyle: labelStyle)
        )
        if abs(statusItem.length - targetLength) > 0.5 {
            statusItem.length = targetLength
        }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func reservedStatusItemLength(mode: DisplayMode, labelStyle: ProviderLabelStyle) -> CGFloat {
        let sampleSnapshot = UsageSnapshot(
            claude: sampleUsage(.claude),
            codex: sampleUsage(.codex),
            updatedAt: Date()
        )

        let image: NSImage
        if labelStyle == .icon {
            image = statusTitleImage(
                segments: statusSegments(
                    snapshot: sampleSnapshot,
                    mode: mode,
                    labelStyle: labelStyle,
                    baseColor: statusTextColor,
                    warningColor: statusWarningColor
                ),
                iconTint: statusTextColor
            )
        } else {
            image = statusTitleImage(
                DisplayFormatter.statusTitle(
                    snapshot: sampleSnapshot,
                    mode: mode,
                    labelStyle: labelStyle
                ),
                color: statusTextColor
            )
        }

        return image.size.width + statusItemHorizontalPadding
    }

    private func sampleUsage(_ provider: Provider) -> ProviderUsage {
        ProviderUsage(
            provider: provider,
            remainingPercent5h: 100,
            remainingPercent7d: 100,
            resetAt5h: nil,
            resetAt7d: nil,
            source: .api,
            error: nil,
            plan: nil,
            model: nil,
            updatedAt: Date()
        )
    }

    private func statusTitleImage(_ title: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = ceilSize((title as NSString).size(withAttributes: attributes))
        let image = NSImage(size: NSSize(width: textSize.width, height: 18))
        image.isTemplate = false

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let y = floor((image.size.height - textSize.height) / 2)
        (title as NSString).draw(
            at: NSPoint(x: 0, y: y),
            withAttributes: attributes
        )
        image.unlockFocus()

        return image
    }

    private func statusTitleImage(segments: [StatusSegment], iconTint: NSColor) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: iconTint
        ]
        let iconSize = NSSize(width: 14, height: 14)
        let spacing: CGFloat = 5
        let separatorSpacing: CGFloat = 8
        let height: CGFloat = 18

        let width = segments.reduce(CGFloat(0)) { total, segment in
            switch segment {
            case .icon:
                return total + iconSize.width + spacing
            case .text(let text, _):
                return total + ceil((text as NSString).size(withAttributes: attributes).width)
            case .separator:
                return total + separatorSpacing + ceil(("·" as NSString).size(withAttributes: attributes).width) + separatorSpacing
            }
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.isTemplate = false
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        var x: CGFloat = 0
        for segment in segments {
            switch segment {
            case .icon(let icon):
                let rect = NSRect(x: x, y: floor((height - iconSize.height) / 2), width: iconSize.width, height: iconSize.height)
                drawIcon(icon, in: rect, tint: iconTint)
                x += iconSize.width + spacing
            case .text(let text, let color):
                var textAttributes = attributes
                textAttributes[.foregroundColor] = color
                let textSize = (text as NSString).size(withAttributes: textAttributes)
                (text as NSString).draw(at: NSPoint(x: x, y: floor((height - textSize.height) / 2)), withAttributes: textAttributes)
                x += ceil(textSize.width)
            case .separator:
                x += separatorSpacing
                let text = "·"
                let textSize = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: x, y: floor((height - textSize.height) / 2)), withAttributes: attributes)
                x += ceil(textSize.width) + separatorSpacing
            }
        }

        image.unlockFocus()
        return image
    }

    private func ceilSize(_ size: NSSize) -> NSSize {
        NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func statusSegments(
        snapshot: UsageSnapshot,
        mode: DisplayMode,
        labelStyle: ProviderLabelStyle,
        baseColor: NSColor,
        warningColor: NSColor
    ) -> [StatusSegment] {
        switch mode {
        case .lowestRemaining:
            let usages = [snapshot.claude, snapshot.codex]
            let lowest = usages.compactMap { DisplayFormatter.displayPercent($0) }.min()
            let color = usages.contains { usage in
                DisplayFormatter.displayPercent(usage) == lowest && DisplayFormatter.displaysSevenDayPercent(usage)
            } ? warningColor : baseColor
            return [.text("AI ", baseColor), .text(DisplayFormatter.formatPercent(lowest), color)]
        case .both:
            if labelStyle == .icon {
                return [
                    .icon(codexIcon),
                    percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor),
                    .separator,
                    .icon(claudeIcon),
                    percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)
                ]
            }
            return [
                .text("\(DisplayFormatter.providerLabel(.codex, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor),
                .separator,
                .text("\(DisplayFormatter.providerLabel(.claude, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)
            ]
        case .codexOnly:
            if labelStyle == .icon {
                return [.icon(codexIcon), percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor)]
            }
            return [
                .text("\(DisplayFormatter.providerLabel(.codex, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor)
            ]
        case .claudeOnly:
            if labelStyle == .icon {
                return [.icon(claudeIcon), percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)]
            }
            return [
                .text("\(DisplayFormatter.providerLabel(.claude, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)
            ]
        }
    }

    private func percentSegment(_ usage: ProviderUsage, baseColor: NSColor, warningColor: NSColor) -> StatusSegment {
        let color = DisplayFormatter.displaysSevenDayPercent(usage)
            ? warningColor
            : baseColor
        return .text(DisplayFormatter.formatPercent(DisplayFormatter.displayPercent(usage)), color)
    }

    private func loadIcon(named name: String) -> NSImage {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: 14, height: 14))
    }

    private func drawIcon(_ icon: NSImage, in rect: NSRect, tint: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        tint.setFill()
        rect.fill()
        icon.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private var statusTextColor: NSColor {
        guard
            let appearance = statusItem.button?.effectiveAppearance,
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        else {
            return .black
        }
        return .white
    }

    private var statusWarningColor: NSColor {
        sevenDayWarningColor
    }
}
