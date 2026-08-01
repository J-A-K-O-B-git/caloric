//
//  ScrollCollapseHeader.swift
//  caloric
//
//  Shared plumbing for headers that shrink as the user scrolls: Dashboard,
//  Daily Journal, Meine Daten.
//
//  Progress is derived directly from the ScrollView's content offset, not
//  driven through a separate withAnimation — that is what makes the collapse
//  track the finger 1:1 instead of lagging or snapping. A threshold-based
//  toggle would be simpler but would look like a jump, not a collapse.
//

import SwiftUI

extension View {
    /// Reports scroll progress (0 = top, 1 = fully collapsed) over `distance`
    /// points of vertical scroll. Attach directly to a ScrollView.
    func trackingHeaderCollapse(progress: Binding<CGFloat>, distance: CGFloat = 60) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
            progress.wrappedValue = min(1, max(0, offset / distance))
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Reports this view's natural height into `height`. Used so a collapsing
    /// header's reserved layout space shrinks together with its content
    /// instead of leaving a growing empty gap above whatever scrolls
    /// underneath it.
    func measuringHeight(into height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self) { height.wrappedValue = $0 }
    }
}
