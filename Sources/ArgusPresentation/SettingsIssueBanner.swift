import SwiftUI

struct SettingsIssueBanner: View {
  let issue: SettingsIssue
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.title3)
        .foregroundStyle(.orange)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 6) {
        Text(issue.title).font(.headline)
        Text(issue.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if let action {
          Button(issue.primaryAction, action: action).buttonStyle(.borderedProminent).controlSize(.small)
        } else {
          Text(issue.primaryAction).font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.orange.opacity(0.35)))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.issue.banner")
  }
}
