import SwiftUI

/// A dropdown in the app's own language. AppKit's menu picker drops a blue
/// system list onto a grained aurora panel, which is jarring enough that people
/// notice the seam before they notice the setting.
struct AuroraSelect<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID?
        let title: String
        var identity: String { String(describing: id) }
    }

    var label: String?
    var options: [Option]
    @Binding var selection: ID?
    var dark: Bool = true

    @State private var open = false

    private var fg: Color { dark ? .white : Aurora.ink }
    private var faint: Color { dark ? .white.opacity(0.5) : Aurora.ink3 }
    private var fill: Color { dark ? .white.opacity(0.08) : .white.opacity(0.75) }
    private var stroke: Color { dark ? .white.opacity(0.18) : Aurora.line }

    private var currentTitle: String {
        options.first { $0.id == selection }?.title ?? options.first?.title ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label.uppercased())
                    .font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(faint)
            }

            Button {
                withAnimation(.smooth(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(currentTitle)
                        .font(Aurora.ui(13, .medium)).foregroundStyle(fg)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(faint)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline, in the flow: opening it pushes the page, and the page is
            // clipped by the panel it sits in. Floating it as an overlay put
            // it underneath the row below, which was worse.
            if open {
                list.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Rows shown before the list scrolls. A provider can return thirty-odd
    /// models; drawn inline at full length they ran off the bottom of the setup
    /// card, which clips, so the lower ones could neither be seen nor chosen.
    private static var visibleRows: Int { 7 }
    private static var rowHeight: CGFloat { 35 }

    @ViewBuilder
    private var list: some View {
        let rows = VStack(spacing: 1) {
            ForEach(options) { option in
                Button {
                    selection = option.id
                    withAnimation(.smooth(duration: 0.2)) { open = false }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(option.id == selection ? 1 : 0)
                        Text(option.title)
                            .font(Aurora.ui(13, .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(fg)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AuroraHoverRow())
                .id(option.identity)
            }
        }
        .padding(5)

        Group {
            if options.count > Self.visibleRows {
                ScrollViewReader { proxy in
                    ScrollView { rows }
                        .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight + 10)
                        .scrollIndicators(.visible)
                        // Open on the current choice, not at the top of a long
                        // list where it might be out of sight.
                        .onAppear {
                            let current = options.first { $0.id == selection }?.identity
                            if let current { proxy.scrollTo(current, anchor: .center) }
                        }
                }
            } else {
                rows
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
    }
}
