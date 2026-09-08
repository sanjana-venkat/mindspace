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

            if open {
                VStack(spacing: 1) {
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
                    }
                }
                .padding(5)
                .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
