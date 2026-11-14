// The iPad's and the Mac's window: the places, the page, the panel beside
// it and the bar under all of it. The iPhone keeps its tabs.

import SwiftUI

extension EnvironmentValues {
    /// Now Playing shown as the wide layout's room, over the places and the
    /// page, with the bar and the panel still beside it: they do its
    /// transport and its panel switch, so it leaves those out.
    @Entry var inRoom = false
}
