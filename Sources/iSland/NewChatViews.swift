import AppKit
import SwiftUI

/// "Start a chat here": the folders you worked in most recently, one click each.
struct NewChatCard: View {
    let folders: [String]
    let onPick: (String) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: IslandLayout.mirrorSpacing) {
            VStack(spacing: IslandLayout.folderRowSpacing) {
                if folders.isEmpty {
                    Text(L10n.t("No recent folders"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(height: IslandLayout.folderRowHeight)
                } else {
                    ForEach(folders, id: \.self) { folder in
                        FolderPickRow(folder: folder).onTapGesture { onPick(folder) }
                    }
                }
            }
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                    Text(L10n.t("Back"))
                }
            }
            .buttonStyle(SubtleButtonStyle())
            .frame(height: IslandLayout.mirrorButtonHeight)
        }
        .padding(.horizontal, IslandLayout.sidePadding)
    }
}

struct FolderPickRow: View {
    let folder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill").font(.system(size: 13)).foregroundStyle(ClaudeSpinner.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(SessionStore.projectName(for: folder))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(parent)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 6)
            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .frame(height: IslandLayout.folderRowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
    }

    private var parent: String {
        ((folder as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    }
}
