import SwiftUI

/// Uses the same searchable French catalog and persistent recents as desktop.
struct MobileEmojiPicker: View {
    let onSelect: (String) -> Void
    var body: some View { MediaEmojiPicker(onSelect: onSelect) }
}
