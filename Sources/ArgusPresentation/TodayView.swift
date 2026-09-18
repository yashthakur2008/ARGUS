import SwiftUI
import ArgusCore

public struct TodayView: View {
  var model: AppModel
  var activation: ActivationController?
  var appearance: AppearanceSettings?
  var voice: VoiceExperienceController?
  var login: LoginItemController?
  @State private var destination: Destination? = .today
  @State private var editor: EditorSession?
  @State private var snooze: SnoozeSession?
  @State private var expandedNow = false
  @State private var expandedApproaching = false

  public init(model: AppModel, activation: ActivationController? = nil, appearance: AppearanceSettings? = nil,
    voice: VoiceExperienceController? = nil, login: LoginItemController? = nil) {
    self.model = model
    self.activation = activation
    self.appearance = appearance
    self.voice = voice
    self.login = login
  }
  public var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 10) {
          Image(systemName: "circle.hexagongrid.fill").font(.title2)
            .foregroundStyle(appearance?.color ?? Color(red: 101 / 255, green: 200 / 255, blue: 145 / 255))
          Text("ARGUS").font(.headline).tracking(3)
        }.padding(.horizontal, 18).padding(.top, 26)
        List(selection: $destination) {
          Label("Today", systemImage: "sun.max").tag(Destination.today)
          Label("All reminders", systemImage: "tray.full").tag(Destination.all)
          Label("Notices", systemImage: "bell.badge").tag(Destination.notices)
          Label("Settings", systemImage: "slider.horizontal.3").tag(Destination.settings)
        }.listStyle(.sidebar)
        VStack(alignment: .leading, spacing: 6) {
          if let activation {
            VoiceStatusOrb(state: voice?.isSpeaking == true ? .speaking : (activation.isListening ? .listening : .off),
              accent: appearance?.color ?? .green, reduceMotion: appearance?.reduceMotion ?? false)
              .accessibilityIdentifier("today.activation.status")
            Text(voice?.statusText ?? activation.statusText)
              .font(.caption2).foregroundStyle(.secondary)
            if activation.isEnabled || voice?.alwaysListen == true || voice?.isSpeaking == true {
              Button("Stop listening") {
                if let voice { voice.stopListening() } else { activation.stop() }
              }
                .font(.caption).accessibilityIdentifier("today.activation.stop")
            } else {
              Button("Activation settings") { destination = .settings }
                .font(.caption)
            }
            Divider().padding(.vertical, 6)
          }
          Label("On this Mac", systemImage: "internaldrive").font(.caption)
          Text("A little less to hold in mind.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18)
      }.navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
    } detail: {
      if destination == .settings { SettingsView(model: model, activation: activation, appearance: appearance, voice: voice, login: login) }
      else if destination == .notices { NoticesView(model: model) }
      else { reminderContent }
    }
    .frame(minWidth: 820, minHeight: 600)
    .tint(appearance?.color ?? Color(red: 101 / 255, green: 200 / 255, blue: 145 / 255))
    .sheet(item: $editor) { session in ReminderEditor(model: model, draft: session.draft) }
    .sheet(item: $snooze) { session in
      SnoozeEditor(model: model, reminder: session.reminder, until: session.until)
    }
    .sheet(isPresented: Binding(
      get: { model.pendingDeletion != nil },
      set: { if !$0 { model.cancelDeletion() } })) {
      VStack(alignment: .leading, spacing: 18) {
        Label("Delete this reminder?", systemImage: "trash").font(.title2.weight(.semibold))
        Text(model.pendingDeletion.map { "“\($0.title)” and its notice history will be removed from this Mac. This cannot be undone." } ?? "")
        Text("Confirmation expires after five minutes. A changed reminder must be reviewed again.")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button("Keep reminder") { model.cancelDeletion() }.keyboardShortcut(.cancelAction)
          Spacer()
          Button("Delete reminder", role: .destructive) { Task { await model.confirmDeletion() } }
            .disabled(model.isWorking)
        }
      }.padding(24).frame(width: 440)
    }
  }

  private var reminderContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text(destination == .all ? "All reminders" : "Today").font(.system(size: 32, weight: .semibold, design: .rounded))
          Text(model.referenceDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
        Button { openEditor(nil) } label: { Label("New reminder", systemImage: "plus") }
          .keyboardShortcut("n", modifiers: .command).buttonStyle(.bordered)
      }
      CommandBar(model: model)
      NoticeView(model: model)
      if model.recovery.attentionCount > 0 {
        Button { destination = .notices } label: {
          HStack {
            Label("\(model.recovery.attentionCount) reminder\(model.recovery.attentionCount == 1 ? " needs" : "s need") attention", systemImage: "bell.badge")
            Spacer()
            Text("Review notices").foregroundStyle(.secondary)
          }.font(.callout).padding(12)
        }.buttonStyle(.plain).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          if destination == .all {
            reminderSection("Everything", subtitle: "Your full local list", items: model.reminders, expanded: .constant(true))
          } else {
            reminderSection("Now", subtitle: "Overdue and the next hour", items: nowItems, expanded: $expandedNow)
            reminderSection("Approaching", subtitle: "The next seven days", items: approachingItems, expanded: $expandedApproaching)
          }
          if model.reminders.isEmpty {
            VStack(spacing: 10) {
              Image(systemName: "checkmark.circle").font(.system(size: 36, weight: .ultraLight))
              Text("Room to focus").font(.title3.weight(.medium))
              Text("Add a reminder above or press ⌘N to choose an exact time.")
                .foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 28)
          }
        }.padding(.bottom, 24)
      }
      HStack {
        Text("⌘K  Command     ⌘N  New reminder").font(.caption2).foregroundStyle(.tertiary)
        Spacer()
        Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r", modifiers: .command)
          .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(30)
  }

  private var nowItems: [Reminder] { (try? ReminderTimeline.nowItems(model.reminders, now: model.referenceDate)) ?? model.reminders }
  private var approachingItems: [Reminder] { (try? ReminderTimeline.approachingItems(model.reminders, now: model.referenceDate)) ?? [] }

  private func reminderSection(_ title: String, subtitle: String, items: [Reminder], expanded: Binding<Bool>) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(title).font(.title3.weight(.semibold))
        Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        Spacer()
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      if items.isEmpty {
        Text("Nothing here right now.").font(.callout).foregroundStyle(.tertiary).padding(.vertical, 14)
      } else {
        VStack(spacing: 0) {
          ForEach(Array((expanded.wrappedValue ? items : Array(items.prefix(5))).enumerated()), id: \.element.id) { index, item in
            if index > 0 { Divider().padding(.leading, 44) }
            reminderRow(item)
          }
        }.background(.background, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        if items.count > 5 {
          Button(expanded.wrappedValue ? "Show fewer" : "Show all \(items.count)") { expanded.wrappedValue.toggle() }
            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func reminderRow(_ item: Reminder) -> some View {
    let date = (try? ReminderTimeline.displayDate(for: item, now: model.referenceDate)) ?? item.dueAt
    return HStack(spacing: 14) {
      Image(systemName: item.recurrence == nil ? "circle" : "repeat")
        .foregroundStyle(date < model.referenceDate ? Color.orange : Color.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 5) {
        Button(item.title) { openEditor(item) }.buttonStyle(.plain).font(.body.weight(.medium))
          .accessibilityLabel("Edit \(item.title)")
        Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TimeZone(identifier: item.timeZoneID) ?? .current)) + " · " + item.timeZoneID)
          .font(.caption).foregroundStyle(date < model.referenceDate ? Color.orange : Color.secondary)
        if item.snoozedUntil != nil { Text("Snoozed · original deadline preserved").font(.caption2).foregroundStyle(.secondary) }
      }
      Spacer(minLength: 12)
      Menu {
        Button("Edit…") { openEditor(item) }
        Button("Snooze 10 minutes") { Task { await model.snooze(item, for: 600) } }
        Button("Snooze 1 hour") { Task { await model.snooze(item, for: 3600) } }
        Button("Snooze until…") { snooze = SnoozeSession(reminder: item, until: model.referenceDate.addingTimeInterval(600)) }
        Divider()
        Button("Delete…", role: .destructive) { model.requestDeletion(item) }
      } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).frame(width: 24)
        .accessibilityLabel("Actions for \(item.title)")
    }.padding(16)
  }

  private func openEditor(_ reminder: Reminder?) {
    editor = EditorSession(draft: ReminderDraft(original: reminder, now: model.referenceDate, timeZone: .current))
  }
}

private enum Destination: Hashable { case today, all, notices, settings }
private struct EditorSession: Identifiable { let id = UUID(); var draft: ReminderDraft }
private struct SnoozeSession: Identifiable { let id = UUID(); let reminder: Reminder; let until: Date }
