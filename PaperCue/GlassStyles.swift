//
//  GlassStyles.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import SwiftUI

struct PaperCueGlassToolbar<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let content: Content
    private let cornerRadius: CGFloat = 28

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            bottomScrim {
                toolbarScrollContent
            }
        } else {
            bottomScrim {
                GlassEffectContainer(spacing: 12) {
                    toolbarScrollContent
                }
            }
        }
    }

    private var toolbarScrollContent: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(toolbarBackground)
            .glassEffectIfAvailable(reduceTransparency: reduceTransparency, cornerRadius: cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func bottomScrim<Toolbar: View>(@ViewBuilder toolbar: () -> Toolbar) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0),
                    Color(.systemBackground).opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 128)
            .allowsHitTesting(false)

            toolbar()
        }
        .frame(maxWidth: .infinity)
    }

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.58))
            }
    }
}

enum PaperCueActionProminence {
    case primary
    case secondary
}

struct PrimaryGlassActionButton: View {
    var title: String
    var systemImage: String
    var tint: Color = .accentColor
    var isDisabled = false
    var prominence: PaperCueActionProminence = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PaperCueActionLabel(
                title: title,
                systemImage: systemImage,
                tint: tint,
                prominence: prominence
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
    }
}

struct PaperCueActionLabel: View {
    var title: String
    var systemImage: String
    var tint: Color = .accentColor
    var prominence: PaperCueActionProminence = .primary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(foregroundStyle)
            .symbolRenderingMode(.hierarchical)
            .frame(minWidth: prominence == .primary ? 84 : 72)
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background(backgroundShape)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderStyle, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var foregroundStyle: Color {
        switch prominence {
        case .primary:
            .white
        case .secondary:
            tint
        }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch prominence {
        case .primary:
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(tint.gradient)
        case .secondary:
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }

    private var borderStyle: Color {
        switch prominence {
        case .primary:
            .white.opacity(0.20)
        case .secondary:
            tint.opacity(0.20)
        }
    }
}

private extension View {
    @ViewBuilder
    func glassEffectIfAvailable(reduceTransparency: Bool, cornerRadius: CGFloat) -> some View {
        if reduceTransparency {
            self
        } else {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct PaperCueIconActionLabel: View {
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tint.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StudyPackSectionView<Content: View, Accessory: View>: View {
    var title: String
    var systemImage: String
    private let content: Content
    private let accessory: Accessory

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.accessory = EmptyView()
    }

    init(
        title: String,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                accessory
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct ReadingStatusBadge: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var status: GenerationStatus

    var body: some View {
        let badge = Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

        if reduceTransparency {
            badge
                .foregroundStyle(color)
                .background(color.opacity(0.12), in: Capsule())
        } else {
            badge
                .foregroundStyle(color)
                .glassEffect(.regular.tint(color.opacity(0.12)), in: Capsule())
        }
    }

    private var color: Color {
        switch status {
        case .completed:
            .green
        case .failed:
            .red
        case .generating, .extracting:
            .orange
        case .ready:
            .blue
        case .idle:
            .secondary
        }
    }
}
