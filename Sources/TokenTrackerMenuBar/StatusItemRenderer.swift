import AppKit
import Foundation
import TokenTrackerCore

private enum StatusSegment {
    case icon(StatusIcon)
    case text(String, NSColor)
    case separator
}

private struct StatusIcon {
    let image: NSImage
    let contentRect: NSRect
}

@MainActor
final class StatusItemRenderer {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var claudeIcon = loadIcon(named: "claudeTemplate@2x")
    private lazy var codexIcon = loadIcon(named: "codexTemplate@2x")
    private let sevenDayWarningColor = NSColor(red: 1.0, green: 0.54, blue: 0.56, alpha: 1.0)
    private let statusItemHorizontalPadding: CGFloat = 4

    func setMenu(_ menu: NSMenu) {
        statusItem.menu = menu
    }

    func setPlaceholder(mode _: DisplayMode, labelStyle _: ProviderLabelStyle) {
        setStatusTitle("AI --")
    }

    func setLoading(mode _: DisplayMode, labelStyle _: ProviderLabelStyle) {
        setStatusTitle("AI ...")
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
                DisplayFormatter.statusTitle(snapshot: snapshot, mode: mode, labelStyle: labelStyle)
            )
        }
    }

    private func setStatusTitle(_ title: String) {
        guard let button = statusItem.button else { return }
        let image = statusTitleImage(title, color: statusTextColor)
        setStatusImage(image, on: button)
    }

    private func setStatusSegments(
        _ segments: [StatusSegment],
        iconTint: NSColor,
        mode: DisplayMode,
        labelStyle: ProviderLabelStyle
    ) {
        guard let button = statusItem.button else { return }
        let image = statusTitleImage(segments: segments, iconTint: iconTint)
        setStatusImage(image, on: button)
    }

    private func setStatusImage(
        _ image: NSImage,
        on button: NSStatusBarButton
    ) {
        let targetLength = ceil(image.size.width + statusItemHorizontalPadding)
        if abs(statusItem.length - targetLength) > 0.5 {
            statusItem.length = targetLength
        }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
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
                DisplayFormatter.displayPercent(usage) == lowest && DisplayFormatter.isSevenDayWarning(usage)
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
        let color = DisplayFormatter.isSevenDayWarning(usage)
            ? warningColor
            : baseColor
        return .text(DisplayFormatter.formatPercent(DisplayFormatter.displayPercent(usage)), color)
    }

    private func loadIcon(named name: String) -> StatusIcon {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return StatusIcon(image: image, contentRect: visibleContentRect(for: image))
        }
        let image = NSImage(size: NSSize(width: 14, height: 14))
        return StatusIcon(image: image, contentRect: NSRect(origin: .zero, size: image.size))
    }

    private func drawIcon(_ icon: StatusIcon, in rect: NSRect, tint: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        tint.setFill()
        rect.fill()
        icon.image.draw(in: rect, from: icon.contentRect, operation: .destinationIn, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func visibleContentRect(for image: NSImage) -> NSRect {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = cgImage.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            return NSRect(origin: .zero, size: image.size)
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        let bytesPerRow = cgImage.bytesPerRow
        let alphaOffset: Int
        switch cgImage.alphaInfo {
        case .first, .premultipliedFirst:
            alphaOffset = 0
        case .none, .noneSkipFirst, .noneSkipLast:
            return NSRect(origin: .zero, size: image.size)
        default:
            alphaOffset = bytesPerPixel - 1
        }
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = bytes[(y * bytesPerRow) + (x * bytesPerPixel) + alphaOffset]
                if alpha > 0 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return NSRect(origin: .zero, size: image.size)
        }

        let scaleX = image.size.width / CGFloat(width)
        let scaleY = image.size.height / CGFloat(height)
        return NSRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(height - maxY - 1) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        )
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
