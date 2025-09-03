/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

// NB: This extension is tailored to our specific use case, SVG
//     containing a single shape with a fill color.
//     For other use cases or full SVG support we should consider a
//     3rd party dependency.

extension UIImage {
    convenience init?(svgData: Data, scale: CGFloat) {
        guard let document = SVGShapeDocument(svgData: svgData) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: document.size, format: format)
        let image = renderer.image { _ in
            let path = UIBezierPath(cgPath: document.path)
            path.usesEvenOddFillRule = document.isEOFilled

            document.fillColor.setFill()
            path.fill()
        }

        guard let cgImage = image.cgImage else {
            return nil
        }

        self.init(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}

private struct SVGShapeDocument {
    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var svgAttributes: [String: String] = [:]
        var pathAttributes: [String: String] = [:]

        private var didParseSVG = false
        private var didParsePath = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName.lowercased() {
            case "svg":
                guard !didParseSVG else {
                    return
                }
                svgAttributes = attributeDict
                didParseSVG = true
            case "path":
                guard !didParsePath else {
                    return
                }
                pathAttributes = attributeDict
                didParsePath = true
            default:
                break
            }
        }
    }

    let size: CGSize
    let path: CGPath
    let fillColor: UIColor
    let isEOFilled: Bool

    init?(svgData: Data) {
        let delegate = ParserDelegate()

        let parser = XMLParser(data: svgData)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return nil
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US_POSIX")
        numberFormatter.numberStyle = .decimal
        numberFormatter.allowsFloats = true

        guard
            let width = delegate.svgAttributes["width"].flatMap(numberFormatter.number(from:))?.doubleValue,
            let height = delegate.svgAttributes["height"].flatMap(numberFormatter.number(from:))?.doubleValue,
            let path = delegate.pathAttributes["d"].flatMap(CGPath.parse(_:)),
            let fillColor = delegate.pathAttributes["fill"]
        else {
            return nil
        }

        self.size = CGSize(width: width, height: height)
        self.path = path
        self.fillColor = UIColor(hexString: fillColor)
        self.isEOFilled = delegate.pathAttributes["fill-rule"]?.lowercased() == "evenodd"
    }
}

extension CGPath {
    fileprivate static func parse(_ d: String) -> CGPath? {
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t\r")
        scanner.locale = Locale(identifier: "en_US_POSIX")

        let path = CGMutablePath()
        var hasSubpath = false

        func nextCommand() -> Character? {
            let uppercase: ClosedRange<Character> = "A"..."Z"
            let lowercase: ClosedRange<Character> = "a"..."z"

            while !scanner.isAtEnd {
                let character = scanner.string[scanner.currentIndex]
                if uppercase.contains(character) || lowercase.contains(character) {
                    scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
                    return character
                }
                scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
            }
            return nil
        }

        func scan() -> CGFloat? {
            scanner.scanDouble().map(CGFloat.init(_:))
        }

        while let command = nextCommand() {
            // Absolute M/L/Q/C only
            switch command {
            case "M":
                guard let x = scan(), let y = scan() else {
                    return nil
                }
                path.move(to: CGPoint(x: x, y: y)); hasSubpath = true
            case "L":
                guard let x = scan(), let y = scan() else {
                    return nil
                }
                path.addLine(to: CGPoint(x: x, y: y))
            case "Q":
                guard
                    let cx = scan(), let cy = scan(),
                    let x = scan(), let y = scan()
                else {
                    return nil
                }
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case "C":
                guard
                    let c1x = scan(), let c1y = scan(),
                    let c2x = scan(), let c2y = scan(),
                    let x = scan(), let y = scan()
                else {
                    return nil
                }
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: c1x, y: c1y),
                    control2: CGPoint(x: c2x, y: c2y)
                )
            case "Z", "z":
                if hasSubpath {
                    path.closeSubpath(); hasSubpath = false
                }
            default:
                return nil // unsupported command
            }
        }

        return path
    }
}
