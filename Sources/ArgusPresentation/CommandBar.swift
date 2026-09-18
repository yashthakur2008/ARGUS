import SwiftUI

struct CommandBar: View {
  @Bindable var model: AppModel
  @FocusState private var focused: Bool
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "text.cursor").foregroundStyle(.secondary)
      TextField("Type a reminder or “help”…", text: $model.commandText)
        .textFieldStyle(.plain)
        .focused($focused)
        .accessibilityLabel("Reminder command")
        .onSubmit { submit() }
      Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
        .buttonStyle(.plain)
        .disabled(model.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
        .accessibilityLabel("Submit reminder command")
      Button("⌘K") { focused = true }
        .keyboardShortcut("k", modifiers: .command)
        .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel("Focus reminder command")
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
  }
  private func submit() { Task { await model.submit(timeZone: .current) } }
}
