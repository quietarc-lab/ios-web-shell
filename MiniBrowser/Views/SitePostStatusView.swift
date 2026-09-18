import SwiftUI

struct SitePostStatusView: View {
    let status: SitePostStatus?
    let automaticStatus: AutomaticPostStatus?

    init(status: SitePostStatus?, automaticStatus: AutomaticPostStatus? = nil) {
        self.status = status
        self.automaticStatus = automaticStatus
    }

    var body: some View {
        Text(displayText)
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 240, height: 28)
            .background(backgroundColor, in: Capsule())
            .shadow(radius: 2)
            .opacity(displayText.isEmpty ? 0 : 1)
            .accessibilityLabel(displayText)
            .allowsHitTesting(false)
    }

    private var backgroundColor: Color {
        if let automaticStatus {
            switch automaticStatus {
            case .completed, .completedUnconfirmed: return .green
            case .stopped: return .red
            case .preparingUA, .checkingCookie, .sending, .cookieRetry,
                 .reconnectingAfterIPLimit, .finalSendAfterIPChange,
                 .switchingAfterAccessRestriction, .switchingAfterContinuousLimit,
                 .reconnectingAfterContinuousLimit,
                 .finalSendAfterContinuousLimit, .waitingForRepeat,
                 .waitingForNextThread, .navigatingToNextThread,
                 .switchingAfterThreadBatch,
                 .refreshingCatalog,
                 .acceptedPendingVerification:
                return .blue
            }
        }
        switch status {
        case .sending: return .yellow
        case .completed: return .green
        case nil: return .clear
        }
    }

    private var foregroundColor: Color {
        if automaticStatus != nil {
            return .white
        }
        switch status {
        case .completed: return .white
        case .sending, nil: return .black
        }
    }

    private var displayText: String {
        automaticStatus?.rawValue ?? status?.rawValue ?? ""
    }
}
