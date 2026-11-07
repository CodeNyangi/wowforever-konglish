import CoreGraphics

// Compare small patches inside recognized message bodies so movement behind
// the translucent chat frame does not move the translations.
struct ChatMotionFrame {
    private let width: Int
    private let height: Int
    private let edges: [Int16]

    init?(image: CGImage, area: CGRect) {
        let width = min(224, image.width)
        let height = min(720, image.height, Int(area.height.rounded()))
        guard width >= 24, height >= 24 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var result = [Int16](repeating: 0, count: pixels.count)
        for row in 0..<height {
            for column in 1..<(width - 1) {
                let index = row * width + column
                let left = pixels[index - 1]
                let right = pixels[index + 1]
                let difference = Int16(right) - Int16(left)
                if max(left, right) >= 120, abs(difference) >= 20 { result[index] = difference }
            }
        }
        self.width = width
        self.height = height
        edges = result
    }

    func shift(to newer: ChatMotionFrame, anchors: [CGRect], in area: CGRect) -> CGFloat? {
        guard width == newer.width, height == newer.height else { return nil }
        let candidates = anchors.filter { $0.width >= 65 && $0.height >= 7 }
        guard candidates.count >= 2 else { return nil }

        let scaleX = CGFloat(width) / area.width
        let scaleY = CGFloat(height) / area.height
        let search = min(height / 3, Int((180 * scaleY).rounded()))
        var votes = [Int](repeating: 0, count: search * 2 + 1)
        var confidence = votes
        let count = min(candidates.count, 7)
        for index in 0..<count {
            let anchor = candidates[index * (candidates.count - 1) / (count - 1)]
            let left = max(1, Int((anchor.minX - area.minX) * scaleX))
            let right = min(width - 1, left + 90, Int((anchor.maxX - area.minX) * scaleX))
            let top = max(0, Int((anchor.minY - area.minY) * scaleY))
            let bottom = min(height, Int((anchor.maxY - area.minY) * scaleY))
            guard right > left, bottom > top else { continue }

            var samples: [(index: Int, edge: Int16)] = []
            var weight = 0
            for y in stride(from: top, to: bottom, by: 2) {
                for x in stride(from: left, to: right, by: 2) {
                    let index = y * width + x
                    let edge = edges[index]
                    if edge != 0 {
                        samples.append((index, edge))
                        weight += Int(abs(edge))
                    }
                }
            }
            guard samples.count >= 16 else { continue }

            let first = max(-top, -search)
            let last = min(height - bottom, search)
            guard first <= last else { continue }
            let scores = (first...last).map { offset -> Int in
                let delta = offset * width
                return samples.reduce(0) { score, sample in
                    let edge = newer.edges[sample.index + delta]
                    return score + ((edge > 0) == (sample.edge > 0) ? Int(min(abs(edge), abs(sample.edge))) : 0)
                }
            }
            guard let best = scores.max(), best * 100 >= weight * 62 else { continue }
            for (index, score) in scores.enumerated() where score * 100 >= weight * 62 && (best - score) * 100 <= weight * 10 {
                let position = first + index + search
                votes[position] += 1
                confidence[position] += score * 1000 / weight
            }
        }
        guard let winner = votes.indices.max(by: { (votes[$0], confidence[$0]) < (votes[$1], confidence[$1]) }),
              votes[winner] >= 2 else { return nil }
        let ambiguous = votes.indices.contains {
            abs($0 - winner) > 2 && votes[$0] == votes[winner] && confidence[winner] - confidence[$0] < votes[winner] * 20
        }
        return ambiguous ? nil : CGFloat(winner - search) / scaleY
    }
}
