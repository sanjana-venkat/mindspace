import SwiftUI

// ============================================================
// NOTED — folders as paper objects
//
// A folder is not a row with a tinted glyph. It is a physical piece of paper
// in one of four stocks, and the stock is the identity: same folder, same
// stock, always, so it is recognisable by shape and colour before the name is
// read. These four and cobalt are the only saturated colour in the app, and
// they never appear on a button, a chip, or any chrome.
//
// The brief points at `assets/folder-*.svg` as the masters. Those files do not
// exist in this repository or anywhere on disk, so the stocks are drawn
// natively below — which is the correct source form for a Swift app in any
// case: they scale to a 24pt thumbnail and a 300pt object from one definition
// rather than from a rasterised import.
// ============================================================

enum FolderStock: CaseIterable {
    case tag        // mustard, punched hole
    case envelope   // brick, square flap
    case receipt    // grey, tear line and stamp
    case card       // cream, ruled

    var paper: Color {
        switch self {
        case .tag: return CanvasPalette.stockTag
        case .envelope: return CanvasPalette.stockEnvelope
        case .receipt: return CanvasPalette.stockReceipt
        case .card: return CanvasPalette.stockCard
        }
    }

    /// Brick is dark enough that warm print black on it fails at small sizes,
    /// so that one stock sets its type in cream instead. Every other stock
    /// takes ink, unchanged.
    var faceInk: Color {
        self == .envelope ? Color(hex: 0xF1EBDD) : CanvasPalette.ink
    }

    var faceInkSoft: Color { faceInk.opacity(0.55) }

    /// The stock a folder is bound to, for the life of the folder.
    ///
    /// Derived from the UUID's own bytes rather than from `Hashable`:
    /// Swift seeds `Hasher` per process, so hashing the id would hand the same
    /// folder a different stock on every launch — which is the one thing this
    /// must never do.
    static func stable(for id: UUID?) -> FolderStock {
        guard let id else {
            // Unfiled is not a folder anyone made, but it is drawn wherever
            // folders are, so it gets a fixed stock of its own.
            return .receipt
        }
        let bytes = withUnsafeBytes(of: id.uuid) { buffer in
            buffer.reduce(into: 0 as UInt32) { total, byte in total &+= UInt32(byte) }
        }
        return allCases[Int(bytes % UInt32(allCases.count))]
    }
}

/// A folder, drawn.
///
/// Proportioned 300 × 380 and scaled from `width`, so a thumbnail and a
/// full-size object are the same drawing at two sizes rather than two
/// drawings. Everything inside is expressed in the 300-wide space and
/// multiplied by `s`.
struct PaperFolderView: View {
    let stock: FolderStock
    let title: String
    let count: Int
    var width: CGFloat = 300
    /// −6° … +4° when folders are fanned; 0° when one is shown on its own.
    var rotation: Double = 0
    /// The surface behind the object, shown through the tag's punched hole.
    var behind: Color = .clear

    @State private var hovering = false

    private var s: CGFloat { width / 300 }
    private var height: CGFloat { width * 380 / 300 }
    private var radius: CGFloat { 12 * s }

    /// Below this the signature details stop being detail and start being
    /// dirt, so a thumbnail carries stock colour, silhouette and the one
    /// structural mark only.
    private var detailed: Bool { s >= 0.34 }
    private var lettered: Bool { s >= 0.55 }

    var body: some View {
        ZStack {
            stock.paper
            stockMarks
            if lettered { face }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // The punch is a real hole: it removes the stock so whatever is behind
        // the object shows through it, rather than painting a circle of the
        // background colour on top.
        .modifier(PunchedHole(active: stock == .tag, diameter: 60 * s, top: 34 * s, behind: behind))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(CanvasPalette.ink.opacity(0.10), lineWidth: 1)
        )
        .rotationEffect(.degrees(rotation))
        // The only shadow permitted anywhere in the app. At rest a folder has
        // none — it is lying on the surface, not floating over it.
        .shadow(color: hovering ? CanvasPalette.folderLift : .clear, radius: 16, x: 0, y: 12)
        .offset(y: hovering ? -4 : 0)
        .animation(CanvasPalette.ease(0.18), value: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: - The face

    /// Name in serif — roman on the first line, italic on the second — and the
    /// note count in mono caps at the bottom left.
    ///
    /// The brief asks for "the app's serif". There isn't one: the four bundled
    /// faces are Boldonse, Hanken Grotesk, Geist Mono and Caveat, and the
    /// display face is a heavy condensed grotesque that would read as the
    /// masthead rather than as a label. The system serif (New York) is used
    /// instead — it needs no licence, it ships with the OS, and the folder
    /// faces are the one place the brief allows a serif at all.
    private var face: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: -4 * s) {
                Text(titleLines.0)
                    .font(.system(size: 40 * s, design: .serif))
                if let second = titleLines.1 {
                    Text(second)
                        .font(.system(size: 40 * s, design: .serif))
                        .italic()
                }
            }
            .foregroundStyle(stock.faceInk)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Spacer(minLength: 0)

            Text(countLabel)
                .font(CanvasTypography.data(11 * s))
                .tracking(1.4 * s)
                .foregroundStyle(stock.faceInkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The tag's punched hole eats the top of the object, so its face
        // starts below the punch rather than under it.
        .padding(.top, (stock == .tag ? 112 : 34) * s)
        .padding(.horizontal, 26 * s)
        .padding(.bottom, 26 * s)
    }

    /// First word roman, the rest italic beneath it. A single-word name simply
    /// has no second line.
    private var titleLines: (String, String?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(of: " ") else { return (trimmed, nil) }
        return (String(trimmed[trimmed.startIndex..<space]),
                String(trimmed[trimmed.index(after: space)...]))
    }

    private var countLabel: String {
        count == 1 ? "1 NOTE" : "\(count) NOTES"
    }

    // MARK: - Signature details

    @ViewBuilder
    private var stockMarks: some View {
        switch stock {
        case .tag: tagMarks
        case .envelope: envelopeMarks
        case .receipt: receiptMarks
        case .card: cardMarks
        }
    }

    /// Mustard, and one small line drawing in the bottom-right corner. The
    /// drawing is a nib — the app's own mark, drawn rather than placed, so it
    /// is a hand on the paper and not an icon dropped onto it.
    @ViewBuilder
    private var tagMarks: some View {
        if detailed {
            NibDrawing()
                .stroke(CanvasPalette.ink.opacity(0.70),
                        style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 46 * s, height: 62 * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 24 * s)
                .padding(.bottom, 22 * s)
        }
    }

    /// Brick, with the square flap drawn as two hairline diagonals running
    /// from the top corners to a meeting point at 34% of the height. A closed
    /// envelope seen from the back.
    @ViewBuilder
    private var envelopeMarks: some View {
        ZStack {
            EnvelopeFlap()
                .stroke(stock.faceInk.opacity(0.42), lineWidth: 1 * s)

            if detailed {
                Text("NOTED · FILED")
                    .font(CanvasTypography.data(9 * s))
                    .tracking(2.2 * s)
                    .foregroundStyle(stock.faceInk.opacity(0.40))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 9 * s)
            }
        }
    }

    /// Grey, with a dashed tear line 44px up from the bottom and a circular
    /// stamp in the top-right corner.
    @ViewBuilder
    private var receiptMarks: some View {
        ZStack {
            Path { path in
                let y = height - 44 * s
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(CanvasPalette.ink.opacity(0.34),
                    style: StrokeStyle(lineWidth: 1, dash: [4 * s, 4 * s]))

            if detailed {
                ReceiptStamp(scale: s)
                    .frame(width: 64 * s, height: 64 * s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 22 * s)
                    .padding(.top, 22 * s)
            }
        }
    }

    /// Cream, ruled every 32px at 9% ink, with one brick header rule — the
    /// index card's red line, in the app's own brick rather than a fifth hue.
    @ViewBuilder
    private var cardMarks: some View {
        Canvas { context, size in
            // Clear of the two-line name above it. On a real index card the
            // heading is written above the header rule, not through it.
            let headerY = 148 * s
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: headerY)); $0.addLine(to: CGPoint(x: size.width, y: headerY)) },
                with: .color(CanvasPalette.stockEnvelope.opacity(0.55)),
                lineWidth: 1
            )
            var y = headerY + 32 * s
            while y < size.height {
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(CanvasPalette.ink.opacity(0.09)),
                    lineWidth: 1
                )
                y += 32 * s
            }
        }
    }
}

// MARK: - Shapes

/// Removes a circle from whatever it is applied to, and shows the surface
/// behind through the gap. `destinationOut` inside a compositing group is what
/// makes it a hole rather than a painted dot.
private struct PunchedHole: ViewModifier {
    let active: Bool
    let diameter: CGFloat
    let top: CGFloat
    let behind: Color

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(alignment: .top) {
                    Circle()
                        .frame(width: diameter, height: diameter)
                        .padding(.top, top)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .background(alignment: .top) {
                    // The rim: paper has thickness at a punch, and without it
                    // the hole reads as a bug rather than as a detail.
                    Circle()
                        .strokeBorder(CanvasPalette.ink.opacity(0.14), lineWidth: 1)
                        .background(Circle().fill(behind))
                        .frame(width: diameter, height: diameter)
                        .padding(.top, top)
                }
        } else {
            content
        }
    }
}

/// Two diagonals from the top corners meeting at 34% of the height.
private struct EnvelopeFlap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let apexY = rect.minY + rect.height * 0.34
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: apexY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A fountain-pen nib: pointed silhouette, a slit down the centre, and the
/// vent hole. Drawn as one open outline so it stays a line drawing.
private struct NibDrawing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let tip = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: CGPoint(x: rect.minX + w * 0.14, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.14, y: rect.minY))
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.46),
            control2: CGPoint(x: rect.midX + w * 0.20, y: rect.minY + h * 0.80)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.14, y: rect.minY),
            control1: CGPoint(x: rect.midX - w * 0.20, y: rect.minY + h * 0.80),
            control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.46)
        )

        // The slit, from the vent hole to the tip.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + h * 0.44))
        path.addLine(to: tip)
        // The vent.
        path.addEllipse(in: CGRect(x: rect.midX - w * 0.10,
                                   y: rect.minY + h * 0.26,
                                   width: w * 0.20, height: h * 0.15))
        return path
    }
}

/// The receipt's stamp: a hairline ring, an inner dashed ring, and the legend
/// set around the outer ring the way a real rubber stamp carries it.
private struct ReceiptStamp: View {
    let scale: CGFloat
    private let legend = "OFFICIAL RECEIPT NO. ___ "

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ink = CanvasPalette.ink.opacity(0.42)

            ZStack {
                Circle().strokeBorder(ink, lineWidth: 1)
                Circle()
                    .strokeBorder(ink, style: StrokeStyle(lineWidth: 1, dash: [2 * scale, 3 * scale]))
                    .padding(side * 0.16)

                // Curved type, a character at a time. At this diameter it is
                // half legend and half texture, which is what a stamp is.
                ForEach(Array(legend.enumerated()), id: \.offset) { index, character in
                    let step = 360.0 / Double(legend.count)
                    Text(String(character))
                        .font(CanvasTypography.data(6.6 * scale))
                        .foregroundStyle(ink)
                        .offset(y: -side * 0.42)
                        .rotationEffect(.degrees(Double(index) * step))
                }
            }
            .frame(width: side, height: side)
        }
    }
}

// MARK: - Thumbnails

/// A folder at row size. Same drawing, same stock, small — which is the point:
/// the folder in the chooser and the folder as an object are one thing.
struct FolderChip: View {
    let stock: FolderStock
    var width: CGFloat = 24

    var body: some View {
        PaperFolderView(stock: stock, title: "", count: 0, width: width)
            .accessibilityHidden(true)
    }
}
