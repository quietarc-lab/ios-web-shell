import SwiftUI
import UIKit

struct ThreadListView: View {
    @ObservedObject var model: ThreadListViewModel
    let onOpenThread: (URL) -> Void
    let sameThreadRepeatEnabled: Bool
    let onToggleSameThreadRepeat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listGrid
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(ThreadListSort.allCases) { sort in
                Button(sort.title) {
                    model.selectSort(sort)
                }
                .font(.caption2.weight(model.selectedSort == sort ? .bold : .regular))
                .foregroundStyle(model.selectedSort == sort ? .white : .primary)
                .accessibilityLabel(sort.accessibilityTitle)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(model.selectedSort == sort ? Color.blue : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Spacer(minLength: 2)

            Button(action: onToggleSameThreadRepeat) {
                Text("同スレ連続")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(sameThreadRepeatEnabled ? .white : .primary)
                    .frame(width: 64, height: 26)
                    .background(sameThreadRepeatEnabled ? Color.blue : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("同スレ連続")
            .accessibilityValue(sameThreadRepeatEnabled ? "オン" : "オフ")
            .accessibilityAddTraits(sameThreadRepeatEnabled ? .isSelected : [])

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Button(action: model.resetOpenHistory) {
                Image(systemName: "arrow.counterclockwise")
            }
            .frame(width: 28, height: 28)
            .accessibilityLabel("閲覧履歴を消去")

            Button(action: model.refresh) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityLabel("カタログを更新")

            Button(action: model.toggleExpanded) {
                Image(systemName: "chevron.down")
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("スレ一覧を閉じる")
        }
        .padding(.horizontal, 5)
        .frame(height: 32)
        .background(.bar)
    }

    private var listGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(model.items) { item in
                    let openCount = model.openCount(for: item)
                    Button {
                        model.recordOpen(item)
                        onOpenThread(item.threadURL)
                    } label: {
                        ThreadListCell(item: item, openCount: openCount)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.openerText ?? "本文取得中")
                }
            }
            .padding(4)
        }
    }
}

private struct ThreadListCell: View {
    let item: ThreadListItem
    let openCount: Int

    var body: some View {
        let hasBeenOpened = openCount > 0
        HStack(spacing: 5) {
            ThreadListThumbnail(item: item)

            Text(item.openerText ?? "本文取得中…")
                .font(.caption2)
                .foregroundStyle(hasBeenOpened ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Text("返信 \(item.replyCount)")
                    .font(.caption2.monospacedDigit())
                if hasBeenOpened {
                    Text("\(openCount)回")
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(hasBeenOpened ? Color.white.opacity(0.9) : Color.secondary)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(hasBeenOpened
                    ? Color(red: 0.03, green: 0.28, blue: 0.62)
                    : Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(hasBeenOpened ? Color.cyan.opacity(0.9) : Color.clear, lineWidth: 1)
        }
    }
}

private struct ThreadListThumbnail: View {
    let item: ThreadListItem

    var body: some View {
        Group {
            if let data = item.thumbnailData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if item.thumbnailLoadFailed {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: 32, height: 32)
        .clipped()
    }
}

struct ThreadListCollapsedBar: View {
    @ObservedObject var model: ThreadListViewModel

    var body: some View {
        Button(action: model.toggleExpanded) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                Text("スレ一覧")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .background(.bar)
        .accessibilityLabel("スレ一覧を開く")
    }
}
