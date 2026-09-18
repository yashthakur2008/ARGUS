import SwiftUI

struct NoticeView: View {
  var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(model.status, systemImage: model.isReconciling ? "arrow.triangle.2.circlepath" : "internaldrive")
        .font(.caption).foregroundStyle(.secondary)
      if let error = model.result?.error {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      }
      if let message = model.message {
        Text(message).font(.callout).textSelection(.enabled)
          .padding(12).frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityLabel("Reminder notice: \(message)")
      }
    }
  }
}
