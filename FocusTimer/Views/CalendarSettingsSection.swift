import AuthenticationServices
import SwiftUI

/// Settings → calendar: link Google Calendar and choose which blocks get logged.
struct CalendarSettingsSection: View {
    let palette: Palette

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @AppStorage(GoogleCalendarService.Key.logFocus) private var logFocus = true
    @AppStorage(GoogleCalendarService.Key.logBreaks) private var logBreaks = false

    private var service: GoogleCalendarService { GoogleCalendarService.shared }

    var body: some View {
        Section {
            if !service.isConfigured {
                Text("Google Calendar isn't set up in this build yet.")
                    .foregroundStyle(palette.dim)
            } else if service.isConnected {
                LabeledContent("google calendar", value: "linked")
                Toggle("log focus blocks", isOn: $logFocus)
                Toggle("log breaks too", isOn: $logBreaks)
                if service.pendingCount > 0 {
                    LabeledContent("waiting to send", value: "\(service.pendingCount)")
                }
                Button("unlink google", systemImage: "xmark.circle", role: .destructive) {
                    Feedback.play(.tap)
                    service.disconnect()
                }
            } else {
                Button {
                    Feedback.play(.tap)
                    Task { await service.connect(using: webAuthenticationSession) }
                } label: {
                    Label("connect google calendar", systemImage: "calendar")
                        .foregroundStyle(palette.accent)
                }
            }
            if let message = service.message {
                Text(message)
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xE0786A))
            }
        } header: {
            Text(palette.style.sectionHeader("calendar"))
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.accent)
        } footer: {
            Text("Each finished focus block becomes an event in a \"Focus\" calendar on your Google account. Focus can only see the calendar it creates.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
        .onChange(of: [logFocus, logBreaks]) { Feedback.play(.tap) }
    }
}
