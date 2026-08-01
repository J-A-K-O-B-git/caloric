//
//  ScrollCollapseHeader.swift
//  caloric
//
//  Shared plumbing for headers that collapse as the user scrolls: Dashboard,
//  Daily Journal, Meine Daten.
//
//  Modelled on the pattern WHOOP uses: the header floats *above* the scroll
//  content rather than sitting in a VStack next to it, so the content passes
//  underneath it and fades out on the way. A compact row stays pinned at the
//  top the whole time while the tall part — title plus full date navigation —
//  shrinks and fades away beneath it.
//
//  Progress comes straight from the scroll offset instead of a withAnimation
//  triggered at a threshold. That is what makes the collapse track the finger
//  1:1 and run backwards just as smoothly; a threshold toggle reads as a jump
//  no matter how the transition itself is eased.
//

import SwiftUI

// MARK: - Scroll tracking

extension View {
    /// Reports scroll progress (0 = top, 1 = fully collapsed) over `distance`
    /// points of vertical scroll. Attach directly to a ScrollView.
    func trackingHeaderCollapse(progress: Binding<CGFloat>, distance: CGFloat) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
            let next = min(1, max(0, offset / max(distance, 1)))
            if abs(next - progress.wrappedValue) > 0.001 {
                progress.wrappedValue = next
            }
        }
    }
}

// MARK: - Height measurement

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Reports this view's natural height, so the collapsing block knows how
    /// far it has to shrink without that distance being hard-coded per screen.
    func measuringHeight(into height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self) { measured in
            if measured > 0, abs(measured - height.wrappedValue) > 0.5 {
                height.wrappedValue = measured
            }
        }
    }
}

// MARK: - Header container

/// Floating header with a permanently pinned row and a collapsing block below.
///
/// `pinned` is always laid out at full size — only its *contents* may react to
/// `progress` (the date label fades in, the profile icon stays put). The
/// `expanding` block shrinks its own reserved height to zero, so nothing is
/// left behind once it is gone.
struct CollapsingHeader<Pinned: View, Expanding: View>: View {

    let progress: CGFloat
    @Binding var expandedHeight: CGFloat
    @ViewBuilder var pinned: () -> Pinned
    @ViewBuilder var expanding: () -> Expanding

    /// Height of the pinned row — also the resting height of the whole header
    /// once the expanding part has collapsed.
    static var pinnedRowHeight: CGFloat { 44 }
    static var topPadding: CGFloat { 14 }
    static var bottomPadding: CGFloat { 10 }

    /// Space the scroll content has to leave free at the top. Kept here so the
    /// three screens using this header do not each restate the paddings.
    static func contentInset(expandedHeight: CGFloat) -> CGFloat {
        topPadding + pinnedRowHeight + expandedHeight + bottomPadding
    }

    var body: some View {
        VStack(spacing: 0) {
            pinned()
                .frame(height: Self.pinnedRowHeight)

            expanding()
                .measuringHeight(into: $expandedHeight)
                .frame(height: expandedHeight * (1 - progress), alignment: .top)
                .opacity(1 - progress)
                .clipped()
        }
        .padding(.horizontal, 20)
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .background(alignment: .top) { backdrop }
    }

    /// Masks whatever scrolls underneath. Transparent at rest, so the app's
    /// gradient background stays unbroken; opaque once the header is acting as
    /// a pinned bar.
    ///
    /// One fill, faded out at its lower edge by a mask. An earlier version
    /// stacked a solid-colour gradient on top of the material to soften that
    /// edge — two different fills that never blended, which showed up as a
    /// hard-edged lighter box below the date.
    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .opacity(progress)
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)
    }
}
