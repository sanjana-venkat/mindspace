import SwiftUI
import AppKit

/// The app mark for the launch sequence.
///
/// The artwork is the app's own icon — ribbons with a pale outline, not
/// uniform strokes — so it is shown rather than redrawn. What is drawn here is
/// the *path* of each ribbon, skeletonised out of the icon itself, and used as
/// a mask: as the paths trim on, the real artwork appears along them. Points
/// are normalised 0…1 in the icon's square, y down.
enum MindspaceMark {
    static let navy = Color(red: 20/255, green: 22/255, blue: 49/255)
    static let mint = Color(red: 168/255, green: 240/255, blue: 205/255)
    /// Wide enough to uncover a whole ribbon plus its outline, tight enough
    /// not to catch the ribbon next to it.
    static let revealWidth: CGFloat = 0.085

    /// The icon as shipped. Nothing else in the app needs it, so it is loaded
    /// once, here.
    static let icon: NSImage? = {
        if let named = Bundle.main.image(forResource: "AppIcon") { return named }
        return NSApp.applicationIconImage
    }()

    static let strokes: [[CGPoint]] = [
    [CGPoint(x: 0.3018, y: 0.3040), CGPoint(x: 0.3047, y: 0.3018), CGPoint(x: 0.3076, y: 0.2997), CGPoint(x: 0.3125, y: 0.2962), CGPoint(x: 0.3184, y: 0.2922), CGPoint(x: 0.3242, y: 0.2884), CGPoint(x: 0.3301, y: 0.2848), CGPoint(x: 0.3359, y: 0.2814), CGPoint(x: 0.3418, y: 0.2781), CGPoint(x: 0.3477, y: 0.2750), CGPoint(x: 0.3535, y: 0.2720), CGPoint(x: 0.3594, y: 0.2690), CGPoint(x: 0.3652, y: 0.2663), CGPoint(x: 0.3711, y: 0.2635), CGPoint(x: 0.3770, y: 0.2611), CGPoint(x: 0.3828, y: 0.2587), CGPoint(x: 0.3887, y: 0.2566), CGPoint(x: 0.3945, y: 0.2546), CGPoint(x: 0.4004, y: 0.2527), CGPoint(x: 0.4062, y: 0.2510), CGPoint(x: 0.4121, y: 0.2493), CGPoint(x: 0.4180, y: 0.2478), CGPoint(x: 0.4238, y: 0.2465), CGPoint(x: 0.4297, y: 0.2451), CGPoint(x: 0.4355, y: 0.2439), CGPoint(x: 0.4414, y: 0.2430), CGPoint(x: 0.4473, y: 0.2421), CGPoint(x: 0.4531, y: 0.2413), CGPoint(x: 0.4590, y: 0.2409), CGPoint(x: 0.4648, y: 0.2401), CGPoint(x: 0.4707, y: 0.2395), CGPoint(x: 0.4766, y: 0.2391), CGPoint(x: 0.4824, y: 0.2387), CGPoint(x: 0.4883, y: 0.2383), CGPoint(x: 0.4941, y: 0.2383), CGPoint(x: 0.5000, y: 0.2383), CGPoint(x: 0.5059, y: 0.2383), CGPoint(x: 0.5117, y: 0.2384), CGPoint(x: 0.5176, y: 0.2388), CGPoint(x: 0.5234, y: 0.2392), CGPoint(x: 0.5293, y: 0.2396), CGPoint(x: 0.5352, y: 0.2404), CGPoint(x: 0.5410, y: 0.2410), CGPoint(x: 0.5469, y: 0.2417), CGPoint(x: 0.5527, y: 0.2424), CGPoint(x: 0.5586, y: 0.2435), CGPoint(x: 0.5645, y: 0.2443), CGPoint(x: 0.5703, y: 0.2454), CGPoint(x: 0.5762, y: 0.2466), CGPoint(x: 0.5820, y: 0.2480), CGPoint(x: 0.5879, y: 0.2495), CGPoint(x: 0.5938, y: 0.2513), CGPoint(x: 0.5996, y: 0.2531), CGPoint(x: 0.6055, y: 0.2551), CGPoint(x: 0.6113, y: 0.2572), CGPoint(x: 0.6172, y: 0.2595), CGPoint(x: 0.6230, y: 0.2618), CGPoint(x: 0.6289, y: 0.2645), CGPoint(x: 0.6348, y: 0.2672), CGPoint(x: 0.6406, y: 0.2701), CGPoint(x: 0.6465, y: 0.2730), CGPoint(x: 0.6523, y: 0.2763), CGPoint(x: 0.6582, y: 0.2797), CGPoint(x: 0.6641, y: 0.2832), CGPoint(x: 0.6699, y: 0.2870), CGPoint(x: 0.6751, y: 0.2913), CGPoint(x: 0.6797, y: 0.2960), CGPoint(x: 0.6827, y: 0.2991), CGPoint(x: 0.6848, y: 0.3018), CGPoint(x: 0.6858, y: 0.3037)],
    [CGPoint(x: 0.2490, y: 0.4004), CGPoint(x: 0.2529, y: 0.4035), CGPoint(x: 0.2578, y: 0.4073), CGPoint(x: 0.2656, y: 0.4126), CGPoint(x: 0.2734, y: 0.4171), CGPoint(x: 0.2812, y: 0.4206), CGPoint(x: 0.2891, y: 0.4233), CGPoint(x: 0.2969, y: 0.4257), CGPoint(x: 0.3047, y: 0.4275), CGPoint(x: 0.3125, y: 0.4288), CGPoint(x: 0.3203, y: 0.4294), CGPoint(x: 0.3281, y: 0.4297), CGPoint(x: 0.3359, y: 0.4293), CGPoint(x: 0.3438, y: 0.4286), CGPoint(x: 0.3516, y: 0.4273), CGPoint(x: 0.3594, y: 0.4255), CGPoint(x: 0.3672, y: 0.4237), CGPoint(x: 0.3750, y: 0.4212), CGPoint(x: 0.3828, y: 0.4188), CGPoint(x: 0.3906, y: 0.4160), CGPoint(x: 0.3984, y: 0.4132), CGPoint(x: 0.4062, y: 0.4100), CGPoint(x: 0.4141, y: 0.4065), CGPoint(x: 0.4219, y: 0.4031), CGPoint(x: 0.4297, y: 0.3995), CGPoint(x: 0.4375, y: 0.3958), CGPoint(x: 0.4453, y: 0.3921), CGPoint(x: 0.4531, y: 0.3882), CGPoint(x: 0.4609, y: 0.3842), CGPoint(x: 0.4688, y: 0.3802), CGPoint(x: 0.4766, y: 0.3760), CGPoint(x: 0.4844, y: 0.3719), CGPoint(x: 0.4922, y: 0.3677), CGPoint(x: 0.5000, y: 0.3637), CGPoint(x: 0.5078, y: 0.3595), CGPoint(x: 0.5156, y: 0.3553), CGPoint(x: 0.5234, y: 0.3512), CGPoint(x: 0.5312, y: 0.3471), CGPoint(x: 0.5391, y: 0.3432), CGPoint(x: 0.5469, y: 0.3393), CGPoint(x: 0.5547, y: 0.3357), CGPoint(x: 0.5625, y: 0.3320), CGPoint(x: 0.5703, y: 0.3285), CGPoint(x: 0.5781, y: 0.3251), CGPoint(x: 0.5859, y: 0.3217), CGPoint(x: 0.5938, y: 0.3189), CGPoint(x: 0.6016, y: 0.3163), CGPoint(x: 0.6094, y: 0.3145), CGPoint(x: 0.6172, y: 0.3128), CGPoint(x: 0.6250, y: 0.3116), CGPoint(x: 0.6328, y: 0.3104), CGPoint(x: 0.6406, y: 0.3099), CGPoint(x: 0.6484, y: 0.3099), CGPoint(x: 0.6562, y: 0.3100), CGPoint(x: 0.6641, y: 0.3105), CGPoint(x: 0.6719, y: 0.3105), CGPoint(x: 0.6768, y: 0.3105), CGPoint(x: 0.6807, y: 0.3105), CGPoint(x: 0.6807, y: 0.3105)],
    [CGPoint(x: 0.2354, y: 0.3928), CGPoint(x: 0.2303, y: 0.3956), CGPoint(x: 0.2227, y: 0.4027), CGPoint(x: 0.2172, y: 0.4141), CGPoint(x: 0.2141, y: 0.4258), CGPoint(x: 0.2130, y: 0.4375), CGPoint(x: 0.2134, y: 0.4492), CGPoint(x: 0.2151, y: 0.4609), CGPoint(x: 0.2191, y: 0.4727), CGPoint(x: 0.2257, y: 0.4844), CGPoint(x: 0.2350, y: 0.4961), CGPoint(x: 0.2461, y: 0.5065), CGPoint(x: 0.2578, y: 0.5143), CGPoint(x: 0.2695, y: 0.5193), CGPoint(x: 0.2812, y: 0.5228), CGPoint(x: 0.2930, y: 0.5259), CGPoint(x: 0.3047, y: 0.5280), CGPoint(x: 0.3164, y: 0.5292), CGPoint(x: 0.3281, y: 0.5293), CGPoint(x: 0.3398, y: 0.5288), CGPoint(x: 0.3516, y: 0.5275), CGPoint(x: 0.3633, y: 0.5250), CGPoint(x: 0.3750, y: 0.5219), CGPoint(x: 0.3867, y: 0.5182), CGPoint(x: 0.3984, y: 0.5143), CGPoint(x: 0.4102, y: 0.5098), CGPoint(x: 0.4219, y: 0.5047), CGPoint(x: 0.4336, y: 0.4992), CGPoint(x: 0.4453, y: 0.4936), CGPoint(x: 0.4570, y: 0.4878), CGPoint(x: 0.4688, y: 0.4819), CGPoint(x: 0.4805, y: 0.4757), CGPoint(x: 0.4922, y: 0.4694), CGPoint(x: 0.5039, y: 0.4634), CGPoint(x: 0.5156, y: 0.4576), CGPoint(x: 0.5273, y: 0.4517), CGPoint(x: 0.5391, y: 0.4458), CGPoint(x: 0.5508, y: 0.4401), CGPoint(x: 0.5625, y: 0.4346), CGPoint(x: 0.5742, y: 0.4296), CGPoint(x: 0.5859, y: 0.4249), CGPoint(x: 0.5977, y: 0.4207), CGPoint(x: 0.6094, y: 0.4168), CGPoint(x: 0.6211, y: 0.4133), CGPoint(x: 0.6328, y: 0.4104), CGPoint(x: 0.6445, y: 0.4085), CGPoint(x: 0.6562, y: 0.4072), CGPoint(x: 0.6680, y: 0.4064), CGPoint(x: 0.6797, y: 0.4066), CGPoint(x: 0.6914, y: 0.4077), CGPoint(x: 0.7031, y: 0.4100), CGPoint(x: 0.7148, y: 0.4135), CGPoint(x: 0.7266, y: 0.4188), CGPoint(x: 0.7383, y: 0.4257), CGPoint(x: 0.7500, y: 0.4346), CGPoint(x: 0.7608, y: 0.4453), CGPoint(x: 0.7697, y: 0.4570), CGPoint(x: 0.7754, y: 0.4688), CGPoint(x: 0.7794, y: 0.4805), CGPoint(x: 0.7824, y: 0.4922), CGPoint(x: 0.7844, y: 0.5039), CGPoint(x: 0.7852, y: 0.5127), CGPoint(x: 0.7852, y: 0.5166)],
    [CGPoint(x: 0.2490, y: 0.5728), CGPoint(x: 0.2539, y: 0.5766), CGPoint(x: 0.2617, y: 0.5824), CGPoint(x: 0.2715, y: 0.5892), CGPoint(x: 0.2812, y: 0.5948), CGPoint(x: 0.2910, y: 0.5992), CGPoint(x: 0.3008, y: 0.6025), CGPoint(x: 0.3105, y: 0.6052), CGPoint(x: 0.3203, y: 0.6074), CGPoint(x: 0.3301, y: 0.6089), CGPoint(x: 0.3398, y: 0.6094), CGPoint(x: 0.3496, y: 0.6094), CGPoint(x: 0.3594, y: 0.6091), CGPoint(x: 0.3691, y: 0.6082), CGPoint(x: 0.3789, y: 0.6065), CGPoint(x: 0.3887, y: 0.6040), CGPoint(x: 0.3984, y: 0.6012), CGPoint(x: 0.4082, y: 0.5978), CGPoint(x: 0.4180, y: 0.5941), CGPoint(x: 0.4277, y: 0.5902), CGPoint(x: 0.4375, y: 0.5861), CGPoint(x: 0.4473, y: 0.5815), CGPoint(x: 0.4570, y: 0.5770), CGPoint(x: 0.4668, y: 0.5724), CGPoint(x: 0.4766, y: 0.5678), CGPoint(x: 0.4863, y: 0.5632), CGPoint(x: 0.4961, y: 0.5586), CGPoint(x: 0.5059, y: 0.5543), CGPoint(x: 0.5156, y: 0.5500), CGPoint(x: 0.5254, y: 0.5458), CGPoint(x: 0.5352, y: 0.5417), CGPoint(x: 0.5449, y: 0.5378), CGPoint(x: 0.5547, y: 0.5340), CGPoint(x: 0.5645, y: 0.5306), CGPoint(x: 0.5742, y: 0.5273), CGPoint(x: 0.5840, y: 0.5245), CGPoint(x: 0.5938, y: 0.5217), CGPoint(x: 0.6035, y: 0.5194), CGPoint(x: 0.6133, y: 0.5173), CGPoint(x: 0.6230, y: 0.5156), CGPoint(x: 0.6328, y: 0.5145), CGPoint(x: 0.6426, y: 0.5132), CGPoint(x: 0.6523, y: 0.5124), CGPoint(x: 0.6621, y: 0.5117), CGPoint(x: 0.6719, y: 0.5117), CGPoint(x: 0.6816, y: 0.5118), CGPoint(x: 0.6914, y: 0.5125), CGPoint(x: 0.7012, y: 0.5135), CGPoint(x: 0.7109, y: 0.5151), CGPoint(x: 0.7207, y: 0.5171), CGPoint(x: 0.7305, y: 0.5197), CGPoint(x: 0.7402, y: 0.5230), CGPoint(x: 0.7500, y: 0.5268), CGPoint(x: 0.7598, y: 0.5306), CGPoint(x: 0.7695, y: 0.5332), CGPoint(x: 0.7777, y: 0.5320), CGPoint(x: 0.7818, y: 0.5311), CGPoint(x: 0.7832, y: 0.5300)],
    [CGPoint(x: 0.2354, y: 0.5662), CGPoint(x: 0.2327, y: 0.5678), CGPoint(x: 0.2303, y: 0.5719), CGPoint(x: 0.2305, y: 0.5801), CGPoint(x: 0.2335, y: 0.5898), CGPoint(x: 0.2378, y: 0.5996), CGPoint(x: 0.2434, y: 0.6094), CGPoint(x: 0.2499, y: 0.6191), CGPoint(x: 0.2574, y: 0.6289), CGPoint(x: 0.2660, y: 0.6387), CGPoint(x: 0.2754, y: 0.6475), CGPoint(x: 0.2852, y: 0.6553), CGPoint(x: 0.2949, y: 0.6615), CGPoint(x: 0.3047, y: 0.6663), CGPoint(x: 0.3145, y: 0.6699), CGPoint(x: 0.3242, y: 0.6728), CGPoint(x: 0.3340, y: 0.6753), CGPoint(x: 0.3438, y: 0.6768), CGPoint(x: 0.3535, y: 0.6776), CGPoint(x: 0.3633, y: 0.6777), CGPoint(x: 0.3730, y: 0.6775), CGPoint(x: 0.3828, y: 0.6766), CGPoint(x: 0.3926, y: 0.6749), CGPoint(x: 0.4023, y: 0.6725), CGPoint(x: 0.4121, y: 0.6699), CGPoint(x: 0.4219, y: 0.6667), CGPoint(x: 0.4316, y: 0.6629), CGPoint(x: 0.4414, y: 0.6587), CGPoint(x: 0.4512, y: 0.6544), CGPoint(x: 0.4609, y: 0.6499), CGPoint(x: 0.4707, y: 0.6451), CGPoint(x: 0.4805, y: 0.6401), CGPoint(x: 0.4902, y: 0.6354), CGPoint(x: 0.5000, y: 0.6306), CGPoint(x: 0.5098, y: 0.6262), CGPoint(x: 0.5195, y: 0.6217), CGPoint(x: 0.5293, y: 0.6174), CGPoint(x: 0.5391, y: 0.6130), CGPoint(x: 0.5488, y: 0.6087), CGPoint(x: 0.5586, y: 0.6048), CGPoint(x: 0.5684, y: 0.6012), CGPoint(x: 0.5781, y: 0.5978), CGPoint(x: 0.5879, y: 0.5945), CGPoint(x: 0.5977, y: 0.5915), CGPoint(x: 0.6074, y: 0.5888), CGPoint(x: 0.6172, y: 0.5865), CGPoint(x: 0.6270, y: 0.5848), CGPoint(x: 0.6367, y: 0.5833), CGPoint(x: 0.6465, y: 0.5824), CGPoint(x: 0.6562, y: 0.5813), CGPoint(x: 0.6660, y: 0.5807), CGPoint(x: 0.6758, y: 0.5809), CGPoint(x: 0.6855, y: 0.5816), CGPoint(x: 0.6953, y: 0.5828), CGPoint(x: 0.7051, y: 0.5842), CGPoint(x: 0.7148, y: 0.5863), CGPoint(x: 0.7246, y: 0.5895), CGPoint(x: 0.7305, y: 0.5916), CGPoint(x: 0.7334, y: 0.5930)],
    [CGPoint(x: 0.5928, y: 0.7732), CGPoint(x: 0.5945, y: 0.7727), CGPoint(x: 0.5954, y: 0.7716), CGPoint(x: 0.5960, y: 0.7704), CGPoint(x: 0.5970, y: 0.7688), CGPoint(x: 0.5982, y: 0.7663), CGPoint(x: 0.5986, y: 0.7633), CGPoint(x: 0.5983, y: 0.7598), CGPoint(x: 0.5973, y: 0.7559), CGPoint(x: 0.5961, y: 0.7520), CGPoint(x: 0.5948, y: 0.7480), CGPoint(x: 0.5934, y: 0.7441), CGPoint(x: 0.5921, y: 0.7402), CGPoint(x: 0.5909, y: 0.7363), CGPoint(x: 0.5896, y: 0.7324), CGPoint(x: 0.5885, y: 0.7285), CGPoint(x: 0.5878, y: 0.7246), CGPoint(x: 0.5871, y: 0.7207), CGPoint(x: 0.5866, y: 0.7168), CGPoint(x: 0.5863, y: 0.7129), CGPoint(x: 0.5863, y: 0.7090), CGPoint(x: 0.5866, y: 0.7051), CGPoint(x: 0.5872, y: 0.7012), CGPoint(x: 0.5882, y: 0.6973), CGPoint(x: 0.5896, y: 0.6934), CGPoint(x: 0.5915, y: 0.6895), CGPoint(x: 0.5940, y: 0.6858), CGPoint(x: 0.5969, y: 0.6824), CGPoint(x: 0.6001, y: 0.6793), CGPoint(x: 0.6036, y: 0.6764), CGPoint(x: 0.6074, y: 0.6740), CGPoint(x: 0.6113, y: 0.6720), CGPoint(x: 0.6152, y: 0.6703), CGPoint(x: 0.6191, y: 0.6690), CGPoint(x: 0.6230, y: 0.6678), CGPoint(x: 0.6270, y: 0.6668), CGPoint(x: 0.6309, y: 0.6659), CGPoint(x: 0.6348, y: 0.6651), CGPoint(x: 0.6387, y: 0.6643), CGPoint(x: 0.6426, y: 0.6634), CGPoint(x: 0.6465, y: 0.6626), CGPoint(x: 0.6504, y: 0.6617), CGPoint(x: 0.6543, y: 0.6609), CGPoint(x: 0.6582, y: 0.6600), CGPoint(x: 0.6621, y: 0.6592), CGPoint(x: 0.6660, y: 0.6583), CGPoint(x: 0.6699, y: 0.6574), CGPoint(x: 0.6738, y: 0.6565), CGPoint(x: 0.6777, y: 0.6555), CGPoint(x: 0.6816, y: 0.6544), CGPoint(x: 0.6855, y: 0.6533), CGPoint(x: 0.6895, y: 0.6521), CGPoint(x: 0.6934, y: 0.6507), CGPoint(x: 0.6973, y: 0.6492), CGPoint(x: 0.7012, y: 0.6477), CGPoint(x: 0.7051, y: 0.6460), CGPoint(x: 0.7090, y: 0.6441), CGPoint(x: 0.7129, y: 0.6421), CGPoint(x: 0.7168, y: 0.6398), CGPoint(x: 0.7207, y: 0.6374), CGPoint(x: 0.7246, y: 0.6349), CGPoint(x: 0.7285, y: 0.6322), CGPoint(x: 0.7314, y: 0.6299), CGPoint(x: 0.7334, y: 0.6284), CGPoint(x: 0.7354, y: 0.6270), CGPoint(x: 0.7373, y: 0.6252), CGPoint(x: 0.7373, y: 0.6252)],
]

}

/// One ribbon's path, so each can be uncovered at its own moment.
struct MindspaceMarkStroke: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let points = MindspaceMark.strokes[index]
        let side = min(rect.width, rect.height)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * side, y: rect.minY + first.y * side))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + p.x * side, y: rect.minY + p.y * side))
        }
        return path
    }
}

/// The mark. `draw` uncovers each ribbon from nothing (0) to whole (1);
/// `plate` brings the rest of the icon — the navy tile — in behind them;
/// `glow` is how much the ribbons still read as light rather than paint.
struct MindspaceMarkView: View {
    var draw: [Double] = Array(repeating: 1, count: MindspaceMark.strokes.count)
    var plate: Double = 1
    var glow: Double = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            ZStack {
                if let icon = MindspaceMark.icon {
                    // The whole icon, arriving underneath once the ribbons are
                    // drawn: the tile appears and the light becomes an object.
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: side, height: side)
                        .opacity(plate)
                        .shadow(color: .black.opacity(0.45 * plate), radius: 30 * plate, y: 14 * plate)

                    // The mark as light, traced on. Where the painted version
                    // exists it is used, added to the sky rather than drawn
                    // over it, so its night background disappears and only the
                    // aurora in it shows. Failing that, the icon's own ribbons
                    // are revealed through the same mask.
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: side, height: side)
                        .mask { trace(side: side) }
                        .blendMode(.plusLighter)
                        .opacity(1 - plate)
                        .shadow(color: MindspaceMark.mint.opacity(glow * 0.85), radius: side * 0.045)
                        .shadow(color: MindspaceMark.mint.opacity(glow * 0.5), radius: side * 0.11)
                } else {
                    // No icon to be had: draw the paths themselves.
                    trace(side: side)
                        .foregroundStyle(MindspaceMark.mint)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func trace(side: CGFloat) -> some View {
        ZStack {
            ForEach(Array(MindspaceMark.strokes.indices), id: \.self) { i in
                MindspaceMarkStroke(index: i)
                    .trim(from: 0, to: draw[i])
                    .stroke(style: StrokeStyle(lineWidth: side * MindspaceMark.revealWidth,
                                               lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: side, height: side)
    }
}
