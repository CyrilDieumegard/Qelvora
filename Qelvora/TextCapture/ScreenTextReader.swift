import AppKit
import CoreGraphics
import Vision

enum ScreenTextReaderError: Error, Equatable {
    case screenCapturePermissionMissing
}

struct ScreenTextReader {
    private let detector = SelectionHighlightDetector()
    private let recognizer = SelectionTextRecognizer()

    @MainActor
    func selectedTextNearPointer(processIdentifier: pid_t?) async throws -> String? {
        guard ScreenCapturePermission.canCaptureScreen else {
            ScreenCapturePermission.requestAndOpenSettings()
            throw ScreenTextReaderError.screenCapturePermissionMissing
        }

        let pointer = CGEvent(source: nil)?.location ?? .zero
        guard let snapshot = ScreenSnapshot.capture(containing: pointer) else {
            return nil
        }

        let pointerPoints = snapshot.imagePoints(forScreenPoint: pointer)
        let searchRects = searchRects(
            processIdentifier: processIdentifier,
            snapshot: snapshot,
            pointerPoints: pointerPoints
        )

        guard let selectionRegion = detector.selectionRegion(
            in: snapshot.image,
            searchRects: searchRects,
            pointerPoints: pointerPoints
        ) else {
            return nil
        }

        let lineRects = selectionRegion.lineRects
            .map { paddedOCRRect(for: $0, in: snapshot.imageBounds) }
            .filter { !$0.isNull && $0.width >= 4 && $0.height >= 4 }

        let cropSourceRect = lineRects.isEmpty
            ? selectionRegion.rect
            : lineRects.reduce(CGRect.null) { $0.union($1) }
        let cropRect = paddedOCRRect(for: cropSourceRect, in: snapshot.imageBounds)

        guard !cropRect.isNull,
              cropRect.width >= 4,
              cropRect.height >= 4,
              let croppedImage = snapshot.image.cropping(to: cropRect) else {
            return nil
        }

        var candidates: [String] = []
        if let lineText = await recognizer.recognizeText(in: snapshot.image, lineRects: lineRects),
           isUsefulOCRText(lineText) {
            candidates.append(lineText)
        }
        if candidates.isEmpty,
           let cropText = await recognizer.recognizeText(in: croppedImage),
           isUsefulOCRText(cropText) {
            candidates.append(cropText)
        }

        let recognizedText = bestSelectionText(from: candidates)
        let trimmedText = recognizedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmedText,
              !isProbablyFailedOCR(trimmedText, cropRect: cropRect) else {
            return nil
        }

        return trimmedText.nilIfEmpty
    }

    private func paddedOCRRect(for rect: CGRect, in imageBounds: CGRect) -> CGRect {
        rect
            .insetBy(dx: -8, dy: -5)
            .intersection(imageBounds)
            .integral
    }

    private func searchRects(
        processIdentifier: pid_t?,
        snapshot: ScreenSnapshot,
        pointerPoints: [CGPoint]
    ) -> [CGRect] {
        var rects: [CGRect] = []

        if let windowFrame = focusedWindowFrame(processIdentifier: processIdentifier) {
            rects.append(contentsOf: snapshot.imageRects(forScreenRect: windowFrame))
        }

        for pointerPoint in pointerPoints {
            rects.append(
                CGRect(
                    x: pointerPoint.x - 850,
                    y: pointerPoint.y - 280,
                    width: 1_700,
                    height: 560
                )
            )
        }

        return rects
            .map { $0.intersection(snapshot.imageBounds).integral }
            .filter { !$0.isNull && $0.width >= 8 && $0.height >= 8 }
            .deduplicatedByRoundedFrame()
    }

    private func focusedWindowFrame(processIdentifier: pid_t?) -> CGRect? {
        guard let processIdentifier else {
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application),
              let position = pointAttribute(kAXPositionAttribute, from: focusedWindow),
              let size = sizeAttribute(kAXSizeAttribute, from: focusedWindow),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func elementAttribute(_ attributeName: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func pointAttribute(_ attributeName: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attributeName: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func isProbablyFailedOCR(_ text: String, cropRect: CGRect) -> Bool {
        cropRect.width >= 90 && text.alphanumericCount <= 1
    }

    private func isUsefulOCRText(_ text: String) -> Bool {
        text
            .components(separatedBy: .newlines)
            .contains { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedLine.alphanumericCount >= 2
                    && !trimmedLine.isMostlyOCRNoise
            }
    }
}

private struct ScreenSnapshot {
    let image: CGImage
    let displayBounds: CGRect

    var imageBounds: CGRect {
        CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    static func capture(containing point: CGPoint) -> ScreenSnapshot? {
        var display = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        let result = CGGetDisplaysWithPoint(point, 1, &display, &displayCount)

        guard result == .success, displayCount > 0, let image = CGDisplayCreateImage(display) else {
            return nil
        }

        return ScreenSnapshot(image: image, displayBounds: CGDisplayBounds(display))
    }

    func imagePoints(forScreenPoint point: CGPoint) -> [CGPoint] {
        let direct = imagePoint(forScreenPoint: point)
        let flipped = CGPoint(x: direct.x, y: CGFloat(image.height) - direct.y)
        return [direct, flipped].deduplicatedByRoundedPoint()
    }

    func imageRects(forScreenRect rect: CGRect) -> [CGRect] {
        let direct = imageRect(forScreenRect: rect)
        let flipped = CGRect(
            x: direct.minX,
            y: CGFloat(image.height) - direct.maxY,
            width: direct.width,
            height: direct.height
        )

        return [direct, flipped].deduplicatedByRoundedFrame()
    }

    private func imagePoint(forScreenPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - displayBounds.minX) * scaleX,
            y: (point.y - displayBounds.minY) * scaleY
        )
    }

    private func imageRect(forScreenRect rect: CGRect) -> CGRect {
        let pointA = imagePoint(forScreenPoint: rect.origin)
        let pointB = imagePoint(forScreenPoint: CGPoint(x: rect.maxX, y: rect.maxY))

        return CGRect(
            x: min(pointA.x, pointB.x),
            y: min(pointA.y, pointB.y),
            width: abs(pointB.x - pointA.x),
            height: abs(pointB.y - pointA.y)
        )
    }

    private var scaleX: CGFloat {
        CGFloat(image.width) / max(displayBounds.width, 1)
    }

    private var scaleY: CGFloat {
        CGFloat(image.height) / max(displayBounds.height, 1)
    }
}

struct SelectionHighlightDetector {
    func selectionRegion(
        in image: CGImage,
        searchRects: [CGRect],
        pointerPoints: [CGPoint]
    ) -> SelectionRegion? {
        guard let raster = RasterImage(image: image) else {
            return nil
        }

        var best: SelectionRegion?

        for searchRect in searchRects {
            guard let region = bestSelectionRegion(
                in: raster,
                searchRect: searchRect,
                pointerPoints: pointerPoints
            ) else {
                continue
            }

            if region.score > (best?.score ?? -.greatestFiniteMagnitude) {
                best = region
            }
        }

        return best?.refined(in: raster)
    }

    private func bestSelectionRegion(
        in raster: RasterImage,
        searchRect: CGRect,
        pointerPoints: [CGPoint]
    ) -> SelectionRegion? {
        let x0 = max(Int(searchRect.minX), 0)
        let y0 = max(Int(searchRect.minY), 0)
        let x1 = min(Int(searchRect.maxX), raster.width)
        let y1 = min(Int(searchRect.maxY), raster.height)
        let width = max(x1 - x0, 0)
        let height = max(y1 - y0, 0)

        guard width > 0, height > 0 else {
            return nil
        }

        var visited = [UInt8](repeating: 0, count: width * height)
        var components: [HighlightComponent] = []

        for y in y0..<y1 {
            for x in x0..<x1 {
                let localIndex = (y - y0) * width + (x - x0)

                guard visited[localIndex] == 0 else {
                    continue
                }

                visited[localIndex] = 1

                guard raster.isSelectionBlue(x: x, y: y) else {
                    continue
                }

                let component = floodFill(
                    raster: raster,
                    startX: x,
                    startY: y,
                    bounds: CGRect(x: x0, y: y0, width: width, height: height),
                    visited: &visited,
                    pointerPoints: pointerPoints
                )

                guard component.isLikelySelection else {
                    continue
                }

                components.append(component)
            }
        }

        var seenRegions = Set<String>()
        let regions = components.compactMap { component -> SelectionRegion? in
            let region = component.selectionRegion(withNearbySelectionComponents: components)

            guard region.isLikelyTextSelectionRegion,
                  seenRegions.insert(region.roundedKey).inserted else {
                return nil
            }

            return region
        }

        guard let best = regions.max(by: { left, right in
            if abs(left.score - right.score) > 0.01 {
                return left.score < right.score
            }

            return left.area < right.area
        }) else {
            return nil
        }

        return best
    }

    private func floodFill(
        raster: RasterImage,
        startX: Int,
        startY: Int,
        bounds: CGRect,
        visited: inout [UInt8],
        pointerPoints: [CGPoint]
    ) -> HighlightComponent {
        let x0 = Int(bounds.minX)
        let y0 = Int(bounds.minY)
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        var queue = [(x: startX, y: startY)]
        var index = 0
        var minX = startX
        var minY = startY
        var maxX = startX
        var maxY = startY
        var pixelCount = 0
        var rowStats: [Int: HighlightRowStats] = [:]

        while index < queue.count {
            let pixel = queue[index]
            index += 1
            pixelCount += 1
            rowStats[pixel.y, default: HighlightRowStats()].include(x: pixel.x)
            minX = min(minX, pixel.x)
            minY = min(minY, pixel.y)
            maxX = max(maxX, pixel.x)
            maxY = max(maxY, pixel.y)

            for neighbor in [
                (pixel.x - 1, pixel.y),
                (pixel.x + 1, pixel.y),
                (pixel.x, pixel.y - 1),
                (pixel.x, pixel.y + 1)
            ] {
                guard neighbor.0 >= x0,
                      neighbor.0 < x0 + width,
                      neighbor.1 >= y0,
                      neighbor.1 < y0 + height else {
                    continue
                }

                let localIndex = (neighbor.1 - y0) * width + (neighbor.0 - x0)
                guard visited[localIndex] == 0 else {
                    continue
                }

                visited[localIndex] = 1

                if raster.isSelectionBlue(x: neighbor.0, y: neighbor.1) {
                    queue.append((neighbor.0, neighbor.1))
                }
            }
        }

        let rect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        return HighlightComponent(
            rect: rect,
            pixelCount: pixelCount,
            rowStats: Array(rowStats.values),
            pointerPoints: pointerPoints
        )
    }
}

struct SelectionRegion {
    let rect: CGRect
    let lineRects: [CGRect]
    let pixelCount: Int
    let pointerPoints: [CGPoint]

    var isLikelyTextSelectionRegion: Bool {
        pixelCount >= 40
            && rect.width >= 10
            && rect.height >= 7
            && longestLineWidth >= 10
            && fillRatio >= 0.45
            && isNearPointer
    }

    var roundedKey: String {
        let frameParts = [
            Int(rect.minX.rounded()),
            Int(rect.minY.rounded()),
            Int(rect.width.rounded()),
            Int(rect.height.rounded())
        ]
        let lineParts = lineRects.map { lineRect in
            [
                Int(lineRect.minX.rounded()),
                Int(lineRect.minY.rounded()),
                Int(lineRect.width.rounded()),
                Int(lineRect.height.rounded())
            ]
                .map(String.init)
                .joined(separator: ":")
        }

        return (frameParts.map(String.init) + lineParts).joined(separator: "|")
    }

    var area: CGFloat {
        rect.width * rect.height
    }

    var score: CGFloat {
        let distance = nearestPointerDistance
        let pointerBonus = pointerPoints.contains { pointerComfortRect.contains($0) } ? 420.0 : 0.0
        let widthBonus = min(longestLineWidth, 900) * 1.1
        let totalWidthBonus = min(lineRects.reduce(CGFloat(0)) { $0 + min($1.width, 900) }, 3_000) * 0.35
        let lineBonus = CGFloat(max(lineRects.count - 1, 0)) * 420.0
        let areaBonus = min(area / 500.0, 700.0)
        let densityBonus = min(CGFloat(pixelCount), 10_000) * 0.04
        let tinySingleLinePenalty = lineRects.count == 1 && longestLineWidth < 85 ? 360.0 : 0.0

        return pointerBonus
            + widthBonus
            + totalWidthBonus
            + lineBonus
            + areaBonus
            + densityBonus
            - tinySingleLinePenalty
            - min(distance, 1_600) * 0.25
    }

    private var longestLineWidth: CGFloat {
        lineRects.map(\.width).max() ?? rect.width
    }

    private var fillRatio: CGFloat {
        let lineArea = lineRects.reduce(CGFloat(0)) { $0 + max($1.width * $1.height, 0) }
        return CGFloat(pixelCount) / max(lineArea, 1)
    }

    private var isNearPointer: Bool {
        pointerPoints.contains { pointerComfortRect.contains($0) }
            || nearestPointerDistance <= pointerDistanceLimit
    }

    private var pointerComfortRect: CGRect {
        rect.insetBy(dx: -180, dy: -120)
    }

    private var pointerDistanceLimit: CGFloat {
        min(max(longestLineWidth * 0.42, 180), 460)
    }

    private var nearestPointerDistance: CGFloat {
        pointerPoints
            .map { point in distance(from: point, to: rect) }
            .min() ?? 1_000
    }

    fileprivate func refined(in raster: RasterImage) -> SelectionRegion {
        let refinedLines = lineRects
            .compactMap { raster.refinedSelectionLineRect(near: $0) }
            .deduplicatedByRoundedFrame()

        guard !refinedLines.isEmpty else {
            return self
        }

        let refinedRect = refinedLines
            .reduce(CGRect.null) { $0.union($1) }
            .integral

        return SelectionRegion(
            rect: refinedRect,
            lineRects: refinedLines,
            pixelCount: pixelCount,
            pointerPoints: pointerPoints
        )
    }
}

private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx: CGFloat
    if point.x < rect.minX {
        dx = rect.minX - point.x
    } else if point.x > rect.maxX {
        dx = point.x - rect.maxX
    } else {
        dx = 0
    }

    let dy: CGFloat
    if point.y < rect.minY {
        dy = rect.minY - point.y
    } else if point.y > rect.maxY {
        dy = point.y - rect.maxY
    } else {
        dy = 0
    }

    return hypot(dx, dy)
}

private struct HighlightComponent {
    let rect: CGRect
    let pixelCount: Int
    let rowStats: [HighlightRowStats]
    let pointerPoints: [CGPoint]

    var isLikelySelection: Bool {
        let area = max(rect.width * rect.height, 1)
        let density = CGFloat(pixelCount) / area
        let minimumWideRows = min(max(Int(rect.height * 0.34), 4), 14)

        return pixelCount >= 40
            && rect.width >= 10
            && rect.height >= 7
            && rect.height <= 90
            && density >= 0.22
            && maxHorizontalRunWidth >= min(max(rect.width * 0.42, 22), 86)
            && wideDenseRowCount >= minimumWideRows
    }

    var score: CGFloat {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let distance = pointerPoints
            .map { hypot(center.x - $0.x, center.y - $0.y) }
            .min() ?? 1_000
        let pointerBonus = pointerPoints.contains { rect.insetBy(dx: -80, dy: -60).contains($0) } ? 1_800.0 : 0.0
        let widthBonus = min(rect.width, 700) * 0.8
        let densityBonus = min(CGFloat(pixelCount), 10_000) * 0.04

        return pointerBonus + widthBonus + densityBonus - distance
    }

    private var maxHorizontalRunWidth: CGFloat {
        rowStats.map(\.span).max() ?? 0
    }

    private var wideDenseRowCount: Int {
        let minimumSpan = min(max(rect.width * 0.34, 18), 72)

        return rowStats.filter { row in
            row.span >= minimumSpan && row.fillRatio >= 0.40
        }.count
    }

    func selectionRegion(withNearbySelectionComponents components: [HighlightComponent]) -> SelectionRegion {
        let lines = HighlightLine.lines(from: components)

        guard let currentIndex = lines.firstIndex(where: { $0.contains(self) }) else {
            return SelectionRegion(
                rect: rect.integral,
                lineRects: [rect.integral],
                pixelCount: pixelCount,
                pointerPoints: pointerPoints
            )
        }

        var lowerBound = currentIndex
        var upperBound = currentIndex

        while lowerBound > 0 {
            let previous = lines[lowerBound - 1]
            let current = lines[lowerBound]
            guard current.isLikelySameSelectionBlock(as: previous) else {
                break
            }

            lowerBound -= 1
        }

        while upperBound < lines.count - 1 {
            let current = lines[upperBound]
            let next = lines[upperBound + 1]
            guard current.isLikelySameSelectionBlock(as: next) else {
                break
            }

            upperBound += 1
        }

        let selectedLines = Array(lines[lowerBound...upperBound])
        let selectedComponents = selectedLines.flatMap(\.components)
        let mergedRect = selectedComponents
            .map(\.rect)
            .reduce(CGRect.null) { $0.union($1) }
            .integral
        let mergedPixelCount = selectedComponents.reduce(0) { $0 + $1.pixelCount }

        return SelectionRegion(
            rect: mergedRect,
            lineRects: selectedLines.map { $0.rect.integral },
            pixelCount: mergedPixelCount,
            pointerPoints: pointerPoints
        )
    }
}

private struct HighlightRowStats {
    private(set) var minX = Int.max
    private(set) var maxX = Int.min
    private(set) var pixelCount = 0

    var span: CGFloat {
        guard minX <= maxX else {
            return 0
        }

        return CGFloat(maxX - minX + 1)
    }

    var fillRatio: CGFloat {
        CGFloat(pixelCount) / max(span, 1)
    }

    mutating func include(x: Int) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        pixelCount += 1
    }
}

private struct HighlightLine {
    private(set) var components: [HighlightComponent]
    private(set) var rect: CGRect
    private(set) var pixelCount: Int

    init(component: HighlightComponent) {
        components = [component]
        rect = component.rect
        pixelCount = component.pixelCount
    }

    static func lines(from components: [HighlightComponent]) -> [HighlightLine] {
        let sortedComponents = components.sorted { left, right in
            if abs(left.rect.midY - right.rect.midY) > 3 {
                return left.rect.midY < right.rect.midY
            }

            return left.rect.minX < right.rect.minX
        }

        var lines: [HighlightLine] = []

        for component in sortedComponents {
            if let index = lines.firstIndex(where: { $0.isOnSameTextLine(as: component) }) {
                lines[index].append(component)
            } else {
                lines.append(HighlightLine(component: component))
            }
        }

        return lines.sorted { left, right in
            if abs(left.rect.minY - right.rect.minY) > 3 {
                return left.rect.minY < right.rect.minY
            }

            return left.rect.minX < right.rect.minX
        }
    }

    mutating func append(_ component: HighlightComponent) {
        components.append(component)
        rect = rect.union(component.rect).integral
        pixelCount += component.pixelCount
    }

    func contains(_ component: HighlightComponent) -> Bool {
        components.contains {
            $0.rect == component.rect && $0.pixelCount == component.pixelCount
        }
    }

    func isLikelySameSelectionBlock(as other: HighlightLine) -> Bool {
        let verticalGap = max(0, max(other.rect.minY - rect.maxY, rect.minY - other.rect.maxY))
        let averageHeight = (rect.height + other.rect.height) / 2
        let allowedGap = min(max(averageHeight * 1.75, 24), 58)

        guard verticalGap <= allowedGap else {
            return false
        }

        let horizontalOverlap = min(rect.maxX, other.rect.maxX) - max(rect.minX, other.rect.minX)
        let minimumWidth = max(min(rect.width, other.rect.width), 1)
        let leftAligned = abs(rect.minX - other.rect.minX) <= max(36, averageHeight * 2.2)
        let rightAligned = abs(rect.maxX - other.rect.maxX) <= max(44, averageHeight * 2.6)
        let oneStartsInsideTheOther = rect.minX <= other.rect.minX && other.rect.minX <= rect.maxX
            || other.rect.minX <= rect.minX && rect.minX <= other.rect.maxX

        return horizontalOverlap >= minimumWidth * 0.24
            || leftAligned
            || rightAligned
            || oneStartsInsideTheOther && horizontalOverlap >= 12
    }

    private func isOnSameTextLine(as component: HighlightComponent) -> Bool {
        let verticalOverlap = min(rect.maxY, component.rect.maxY) - max(rect.minY, component.rect.minY)
        let minimumHeight = min(rect.height, component.rect.height)
        let centerDistance = abs(rect.midY - component.rect.midY)
        let lineTolerance = max(rect.height, component.rect.height) * 0.75

        return verticalOverlap >= minimumHeight * 0.35 || centerDistance <= lineTolerance
    }
}

private struct RasterImage {
    let width: Int
    let height: Int
    private let bytesPerPixel = 4
    private let pixels: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height

        guard width > 0, height > 0 else {
            return nil
        }

        var pixelBuffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixelBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = pixelBuffer
    }

    func isSelectionBlue(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else {
            return false
        }

        let index = (y * width + x) * bytesPerPixel
        let red = Int(pixels[index])
        let green = Int(pixels[index + 1])
        let blue = Int(pixels[index + 2])
        let maxChannel = max(red, max(green, blue))
        let minChannel = min(red, min(green, blue))

        return blue >= 105
            && blue - red >= 35
            && green - red >= 10
            && maxChannel - minChannel >= 45
    }

    func refinedSelectionLineRect(near rect: CGRect) -> CGRect? {
        let scanRect = rect
            .insetBy(dx: -260, dy: -8)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            .integral

        guard !scanRect.isNull,
              scanRect.width >= 4,
              scanRect.height >= 4 else {
            return nil
        }

        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min
        var bluePixelCount = 0

        let x0 = max(Int(scanRect.minX), 0)
        let y0 = max(Int(scanRect.minY), 0)
        let x1 = min(Int(scanRect.maxX), width)
        let y1 = min(Int(scanRect.maxY), height)

        for y in y0..<y1 {
            for x in x0..<x1 where isSelectionBlue(x: x, y: y) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                bluePixelCount += 1
            }
        }

        guard bluePixelCount >= 30,
              minX <= maxX,
              minY <= maxY else {
            return rect.integral
        }

        return rect
            .union(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            .integral
    }
}

private struct SelectionTextRecognizer {
    func recognizeText(in image: CGImage, lineRects: [CGRect]) async -> String? {
        guard !lineRects.isEmpty else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            let lineTexts = lineRects
                .sorted { left, right in
                    if abs(left.minY - right.minY) > 3 {
                        return left.minY < right.minY
                    }

                    return left.minX < right.minX
                }
                .compactMap { lineRect -> RecognizedLineText? in
                    guard let croppedLine = image.cropping(to: lineRect) else {
                        return nil
                    }

                    return recognizeTextSynchronously(inSelectedCrop: croppedLine)
                        .map { RecognizedLineText(rect: lineRect, text: $0.text, confidence: $0.confidence) }
                }

            return joinedVisualLineText(from: lineTexts)
        }.value
    }

    func recognizeText(in image: CGImage) async -> String? {
        await Task.detached(priority: .userInitiated) {
            recognizeTextSynchronously(inSelectedCrop: image)?.text
        }.value
    }
}

private struct RecognizedLineText {
    let rect: CGRect
    let text: String
    let confidence: Float
}

private func joinedVisualLineText(from lines: [RecognizedLineText]) -> String? {
    let lines = lines
        .map {
            RecognizedLineText(
                rect: $0.rect,
                text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: $0.confidence
            )
        }
        .filter { !$0.text.isEmpty }
        .filter { !$0.text.isMostlyOCRNoise || $0.confidence >= 0.58 }

    guard !lines.isEmpty else {
        return nil
    }

    let sortedLines = lines.sorted { left, right in
        if abs(left.rect.minY - right.rect.minY) > 3 {
            return left.rect.minY < right.rect.minY
        }

        return left.rect.minX < right.rect.minX
    }

    let sortedHeights = sortedLines
        .map(\.rect.height)
        .sorted()
    let medianHeight = sortedHeights[sortedHeights.count / 2]
    let paragraphGap = max(medianHeight * 1.2, 20)

    var outputLines: [String] = []

    for (index, line) in sortedLines.enumerated() {
        if index > 0 {
            let previous = sortedLines[index - 1]
            let gap = max(0, line.rect.minY - previous.rect.maxY)

            if gap >= paragraphGap {
                outputLines.append("")
            }
        }

        outputLines.append(line.text)
    }

    return outputLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty
}

private func recognizeTextSynchronously(inSelectedCrop image: CGImage) -> RecognizedTextCandidate? {
    let maskedImage = highContrastImage(from: image)
    let dilatedMaskedImage = highContrastImage(from: image, dilationRadius: 1)

    let maskedCandidates = [
        dilatedMaskedImage.flatMap { scaledImage(from: $0, scale: 2) },
        maskedImage.flatMap { scaledImage(from: $0, scale: 2) },
        maskedImage
    ].compactMap { $0 }
        .flatMap { image in
            [
                recognizedTextSynchronously(
                    in: image,
                    recognitionLevel: .accurate,
                    usesLanguageCorrection: true
                )
            ]
            .compactMap { $0 }
        }

    return bestText(in: maskedCandidates)
}

private struct RecognizedTextCandidate {
    let text: String
    let confidence: Float
}

private func highContrastImage(from image: CGImage, dilationRadius: Int = 0) -> CGImage? {
    guard let raster = MutableRasterImage(image: image) else {
        return nil
    }

    return raster.selectionTextMask(dilationRadius: dilationRadius)
}

private func recognizedTextSynchronously(
    in image: CGImage,
    recognitionLevel: VNRequestTextRecognitionLevel,
    usesLanguageCorrection: Bool
) -> RecognizedTextCandidate? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = recognitionLevel
    request.usesLanguageCorrection = usesLanguageCorrection
    request.recognitionLanguages = ["fr-FR", "en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])

    do {
        try handler.perform([request])
    } catch {
        return nil
    }

    let results = (request.results ?? [])
        .compactMap { observation -> (text: String, box: CGRect, confidence: Float)? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (text, observation.boundingBox, candidate.confidence)
        }
        .sorted { left, right in
            if abs(left.box.midY - right.box.midY) > 0.035 {
                return left.box.midY > right.box.midY
            }

            return left.box.minX < right.box.minX
        }

    let text = results
        .map(\.text)
        .joined(separator: " ")
        .nilIfEmpty

    guard let text else {
        return nil
    }

    let averageConfidence = results.isEmpty
        ? 0
        : results.reduce(Float(0)) { $0 + $1.confidence } / Float(results.count)

    return RecognizedTextCandidate(text: text, confidence: averageConfidence)
}

private func scaledImage(from image: CGImage, scale: CGFloat) -> CGImage? {
    guard scale > 1 else {
        return image
    }

    let width = Int(CGFloat(image.width) * scale)
    let height = Int(CGFloat(image.height) * scale)
    let bytesPerPixel = 4
    var pixelBuffer = [UInt8](repeating: 255, count: width * height * bytesPerPixel)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: &pixelBuffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    return context.makeImage()
}

private func bestText(in candidates: [RecognizedTextCandidate]) -> RecognizedTextCandidate? {
    candidates
        .map {
            RecognizedTextCandidate(
                text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: $0.confidence
            )
        }
        .filter { !$0.text.isEmpty }
        .filter { !$0.text.isMostlyOCRNoise || $0.confidence >= 0.58 }
        .max { left, right in
            let leftScore = left.ocrScore
            let rightScore = right.ocrScore
            return leftScore == rightScore ? left.text.count < right.text.count : leftScore < rightScore
        }
}

private func bestSelectionText(from candidates: [String]) -> String? {
    let candidates = candidates
        .map(cleanedSelectionOCRText)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard let longestCandidate = candidates.max(by: { $0.alphanumericCount < $1.alphanumericCount }) else {
        return nil
    }

    let linePreservingCandidate = candidates
        .filter { $0.contains("\n") }
        .max(by: { $0.alphanumericCount < $1.alphanumericCount })

    if let linePreservingCandidate,
       linePreservingCandidate.alphanumericCount >= Int(Double(longestCandidate.alphanumericCount) * 0.90) {
        return linePreservingCandidate
    }

    return longestCandidate
}

private func cleanedSelectionOCRText(_ text: String) -> String {
    text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { !$0.isMostlyOCRNoise }
        .joined(separator: "\n")
}

private extension RecognizedTextCandidate {
    var ocrScore: Double {
        let noisePenalty = text.isMostlyOCRNoise ? 24.0 : 0.0
        return Double(text.alphanumericCount) + Double(confidence) * 28 - noisePenalty
    }
}

private extension String {
    var alphanumericCount: Int {
        filter { $0.isLetter || $0.isNumber }.count
    }

    var isMostlyOCRNoise: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let alphanumericCount = trimmed.alphanumericCount
        guard alphanumericCount > 0 else {
            return true
        }

        if trimmed.count <= 4 && alphanumericCount <= 1 {
            return true
        }

        let punctuationCount = trimmed.filter {
            !$0.isLetter && !$0.isNumber && !$0.isWhitespace
        }.count
        if alphanumericCount <= 3 && punctuationCount >= 2 {
            return true
        }

        let symbolNoiseCount = trimmed.filter { "'`=|~".contains($0) }.count
        if symbolNoiseCount >= 2 && alphanumericCount <= 8 {
            return true
        }

        return false
    }
}

private struct MutableRasterImage {
    let width: Int
    let height: Int
    private let bytesPerPixel = 4
    private var pixels: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height

        guard width > 0, height > 0 else {
            return nil
        }

        pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func selectionTextMask(dilationRadius: Int = 0) -> CGImage? {
        let dilationRadius = max(dilationRadius, 0)
        var selectionMask = [UInt8](repeating: 0, count: width * height)
        var textMask = [UInt8](repeating: 0, count: width * height)
        var output = [UInt8](repeating: 255, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])

                if isSelectionBlue(red: red, green: green, blue: blue) {
                    selectionMask[y * width + x] = 1
                }
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])

                if isLightSelectionText(red: red, green: green, blue: blue),
                   containsPixel(in: selectionMask, x: x, y: y, radius: 9) {
                    textMask[y * width + x] = 1
                }
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                guard containsTextPixel(in: textMask, x: x, y: y, radius: dilationRadius) else {
                    continue
                }

                let index = (y * width + x) * bytesPerPixel
                output[index] = 0
                output[index + 1] = 0
                output[index + 2] = 0
                output[index + 3] = 255
            }
        }

        let providerData = Data(output) as CFData
        guard let provider = CGDataProvider(data: providerData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func isSelectionBlue(red: Int, green: Int, blue: Int) -> Bool {
        let maxChannel = max(red, max(green, blue))
        let minChannel = min(red, min(green, blue))

        return blue >= 105
            && blue - red >= 35
            && green - red >= 10
            && maxChannel - minChannel >= 45
    }

    private func isLightSelectionText(red: Int, green: Int, blue: Int) -> Bool {
        red >= 118 && green >= 118 && blue >= 118 && max(red, max(green, blue)) - min(red, min(green, blue)) <= 105
    }

    private func containsTextPixel(in textMask: [UInt8], x: Int, y: Int, radius: Int) -> Bool {
        containsPixel(in: textMask, x: x, y: y, radius: radius)
    }

    private func containsPixel(in mask: [UInt8], x: Int, y: Int, radius: Int) -> Bool {
        let minX = max(x - radius, 0)
        let maxX = min(x + radius, width - 1)
        let minY = max(y - radius, 0)
        let maxY = min(y + radius, height - 1)

        for candidateY in minY...maxY {
            for candidateX in minX...maxX where mask[candidateY * width + candidateX] == 1 {
                return true
            }
        }

        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == CGPoint {
    func deduplicatedByRoundedPoint() -> [CGPoint] {
        var seen = Set<String>()
        return filter { point in
            seen.insert("\(Int(point.x.rounded())):\(Int(point.y.rounded()))").inserted
        }
    }
}

private extension Array where Element == CGRect {
    func deduplicatedByRoundedFrame() -> [CGRect] {
        var seen = Set<String>()
        return filter { rect in
            let key = [
                Int(rect.minX.rounded()),
                Int(rect.minY.rounded()),
                Int(rect.width.rounded()),
                Int(rect.height.rounded())
            ]
                .map(String.init)
                .joined(separator: ":")

            return seen.insert(key).inserted
        }
    }
}
