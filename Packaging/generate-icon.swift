import AppKit
import CoreImage
import UniformTypeIdentifiers

// Generates the OhMyDisplay app icon (1024x1024 PNG): a dithered dot-matrix screen in a brushed-silver
// frame, a soft diagonal light band crossing a faint "omd". Usage: swift generate-icon.swift <output.png>

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(width: Int, height: Int) -> CGContext {
  CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Blends a color toward its own luma, cutting saturation without losing brightness
func muted(_ hex: UInt32, by amount: CGFloat = 0.60) -> CGColor {
  let red = CGFloat((hex >> 16) & 0xFF) / 255
  let green = CGFloat((hex >> 8) & 0xFF) / 255
  let blue = CGFloat(hex & 0xFF) / 255
  let gray = 0.299 * red + 0.587 * green + 0.114 * blue
  return CGColor(
    srgbRed: red + (gray - red) * amount, green: green + (gray - green) * amount,
    blue: blue + (gray - blue) * amount, alpha: 1)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> CGPath {
  CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func stroked(_ path: CGPath, width: CGFloat) -> CGPath {
  path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func fill(_ context: CGContext, _ path: CGPath, with colors: [CGColor], from start: CGPoint, to end: CGPoint) {
  context.saveGState()
  context.addPath(path)
  context.clip()
  context.drawLinearGradient(
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!,
    start: start, end: end, options: [])
  context.restoreGState()
}

let platePath = rounded(100, 100, 824, 824, radius: 184)
let sweep = [muted(0x16C3E0), muted(0x3D6BFF), muted(0x8E54E9), muted(0xFF5C8F)]

let displayShape: CGPath = {
  let shape = CGMutablePath()
  shape.addPath(stroked(rounded(212, 341, 600, 400, radius: 44), width: 32))
  shape.addPath(rounded(372, 267, 280, 32, radius: 16))
  return shape
}()
let sweepStart = CGPoint(x: 196, y: 267)
let sweepEnd = CGPoint(x: 828, y: 757)
let screenInterior = rounded(228, 357, 568, 368, radius: 28)

// Piecewise-linear interpolation across the sweep palette
func sweepColor(_ t: CGFloat, alpha: CGFloat) -> CGColor {
  let scaled = min(max(t, 0), 1) * CGFloat(sweep.count - 1)
  let index = min(Int(scaled), sweep.count - 2)
  let fraction = scaled - CGFloat(index)
  let from = sweep[index].components!
  let to = sweep[index + 1].components!
  return CGColor(
    srgbRed: from[0] + (to[0] - from[0]) * fraction, green: from[1] + (to[1] - from[1]) * fraction,
    blue: from[2] + (to[2] - from[2]) * fraction, alpha: alpha)
}

let context = makeContext(width: 1024, height: 1024)

// Plate
fill(
  context, platePath, with: [rgb(0x2C3140), rgb(0x0F1117)],
  from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

// Soft neon bloom spilling from the frame, confined to the screen interior
let bloomLayer = makeContext(width: 1024, height: 1024)
fill(bloomLayer, displayShape, with: sweep, from: sweepStart, to: sweepEnd)
let blur = CIFilter(name: "CIGaussianBlur")!
blur.setValue(CIImage(cgImage: bloomLayer.makeImage()!).clampedToExtent(), forKey: kCIInputImageKey)
blur.setValue(24.0, forKey: kCIInputRadiusKey)
let blurOutput = blur.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let ciContext = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
let blurred = ciContext.createCGImage(blurOutput, from: blurOutput.extent)!
context.saveGState()
context.addPath(screenInterior)
context.clip()
context.setAlpha(0.55)
context.draw(blurred, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.restoreGState()

// LED matrix: a faint "omd" in the bottom-right corner of a dim dithered gradient (3x5 dot-matrix font)
let glyphs = [
  [".#.", "#.#", "#.#", "#.#", ".#."],  // O
  ["#.#", "###", "#.#", "#.#", "#.#"],  // M
  ["##.", "#.#", "#.#", "#.#", "##."],  // D
]
let columns = 23
let rows = 15
var lit = Set<Int>()
var cursor = 10  // 2-cell margins right and bottom; glyph row 0 is the top, grid rows count bottom-up
for glyph in glyphs {
  for (glyphRow, line) in glyph.enumerated() {
    for (offset, character) in line.enumerated() where character == "#" {
      lit.insert((2 + 4 - glyphRow) * columns + cursor + offset)
    }
  }
  cursor += 4  // 3 cells wide + 1 gap
}

let bayer: [[CGFloat]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
let cell: CGFloat = 24
let originX = 228 + (568 - CGFloat(columns) * cell) / 2
let originY = 357 + (368 - CGFloat(rows) * cell) / 2
context.saveGState()
context.addPath(screenInterior)
context.clip()
for row in 0..<rows {
  for column in 0..<columns {
    let t = (CGFloat(column) / CGFloat(columns - 1) + CGFloat(row) / CGFloat(rows - 1)) / 2
    let quantized = CGFloat(min(4, Int(t * 5 + bayer[row % 4][column % 4] / 16))) / 4  // 5 levels + ordered dither
    let isLit = lit.contains(row * columns + column)
    // A soft diagonal light band sweeps the matrix; "omd" stays a notch bolder
    let band = exp(-pow(CGFloat(column - row) - 11, 2) / 24.5)
    context.setFillColor(sweepColor(quantized, alpha: isLit ? 0.44 + 0.34 * band : 0.16 + 0.26 * band))
    context.addPath(
      rounded(originX + CGFloat(column) * cell + 2, originY + CGFloat(row) * cell + 2, cell - 4, cell - 4, radius: 5))
    context.fillPath()
  }
}
context.restoreGState()

// Display outline and base line, brushed silver
fill(
  context, displayShape, with: [rgb(0xEDF0F4), rgb(0x9AA3B2)],
  from: CGPoint(x: 512, y: 757), to: CGPoint(x: 512, y: 267))

// Hairline rim light along the top inner edge of the plate
context.saveGState()
context.addPath(platePath)
context.clip()
fill(
  context, stroked(platePath, width: 6),
  with: [rgb(0xFFFFFF, alpha: 0.30), rgb(0xFFFFFF, alpha: 0)],
  from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 460))
context.restoreGState()

let destination = CGImageDestinationCreateWithURL(
  URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Failed to write PNG") }
