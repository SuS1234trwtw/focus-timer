import SwiftUI

/// Settings → account: guest by default, optional email account for backup & sync across devices.
struct AccountSettingsSection: View {
    let palette: Palette

    @AppStorage(OnboardingGate.key) private var onboardingDone = false
    @State private var showForm = false
    @State private var confirmSignOut = false

    private var account: AccountService { AccountService.shared }

    var body: some View {
        Section {
            if !account.isAvailable {
                Text("sync isn't set up in this build, so everything stays on this iPhone.")
                    .foregroundStyle(palette.dim)
            } else if account.isGuest {
                LabeledContent("account", value: "guest")
                if showForm || account.pendingEmail != nil {
                    AccountForm(palette: palette)
                } else {
                    Button {
                        Feedback.play(.tap)
                        account.clearMessage()
                        withAnimation(Motion.fast) { showForm = true }
                    } label: {
                        Label("set up backup & sync", systemImage: "person.badge.key")
                            .foregroundStyle(palette.accent)
                    }
                    messageLine
                }
            } else {
                LabeledContent("account", value: account.email ?? "?")
                Button("sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Feedback.play(.tap)
                    confirmSignOut = true
                }
                .disabled(account.busy)
                if account.busy {
                    ProgressView().tint(palette.accent)
                }
                messageLine
            }
            Button {
                Feedback.play(.tap)
                onboardingDone = false
            } label: {
                Label("run setup again", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(palette.accent)
            }
        } header: {
            Text(palette.style.sectionHeader("account"))
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.accent)
        } footer: {
            Text("As a guest, tasks live on this iPhone and only this install can reach its backup. With an account, they sync to every iPhone and iPad running Focus. You sign in with a 6-digit code sent to your email: no password. Signing out keeps your tasks here.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
        .task { await account.refresh() }
        .onChange(of: account.isGuest) { _, guest in
            if !guest { showForm = false }
        }
        .confirmationDialog("sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("sign out", role: .destructive) {
                Task { await account.signOut() }
            }
        } message: {
            Text("Your tasks stay on this iPhone. Log in again any time with a code to sync.")
        }
    }

    @ViewBuilder private var messageLine: some View {
        if let message = account.message {
            Text(message)
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(account.messageIsError ? Color(hex: 0xE0786A) : palette.dim)
        }
    }
}

/// Create an account or log in with a 6-digit email code: email first, then the code.
/// Used in Settings and in the setup guide.
struct AccountForm: View {
    let palette: Palette

    @State private var mode: AccountService.Mode = .create
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    private var account: AccountService { AccountService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = account.pendingEmail {
                codeStep(pending)
            } else {
                emailStep
            }
            if let message = account.message {
                Text(message)
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(account.messageIsError ? Color(hex: 0xE0786A) : palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("no password: we email you a 6-digit code. sync works on every iPhone and iPad running Focus.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(palette.mono(15, relativeTo: .body))
        .padding(.vertical, 4)
        .onChange(of: mode) {
            Feedback.play(.tap)
            account.clearMessage()
        }
    }

    // MARK: Steps

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("account", selection: $mode) {
                ForEach(AccountService.Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            field {
                TextField("email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($focused, equals: .email)
                    .onSubmit(sendCode)
            }
            submitButton("send code", action: sendCode)
        }
    }

    private func codeStep(_ pending: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("enter the 6-digit code sent to \(pending)")
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)

            field {
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    // iOS offers the code from Mail right above the keyboard.
                    .textContentType(.oneTimeCode)
                    .font(palette.mono(28, .bold, relativeTo: .title))
                    .tracking(8)
                    .multilineTextAlignment(.center)
                    .focused($focused, equals: .code)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        // Paste or autofill: submit as soon as all six digits are in.
                        if digits.count == 6, !account.busy { verify() }
                    }
            }
            submitButton(account.pendingMode == .create ? "create account" : "log in", action: verify)

            HStack {
                // Re-renders every second while the cooldown runs.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let wait = account.resendWait(now: context.date)
                    Button(wait > 0 ? "resend code (\(wait)s)" : "resend code") {
                        Feedback.play(.tap)
                        code = ""
                        Task { await account.sendCode(email: pending, mode: account.pendingMode) }
                    }
                    .disabled(wait > 0 || account.busy)
                }
                Spacer()
                Button("use a different email") {
                    Feedback.play(.tap)
                    code = ""
                    email = pending
                    account.cancelCode()
                }
                .disabled(account.busy)
            }
            .font(palette.mono(12, relativeTo: .footnote))
            .foregroundStyle(palette.accent)
            .buttonStyle(.plain)
        }
        .onAppear { focused = .code }
    }

    // MARK: Pieces

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(palette.mono(15, relativeTo: .body))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(palette.background, in: .rect(cornerRadius: palette.style.radius(6)))
            .overlay {
                RoundedRectangle(cornerRadius: palette.style.radius(6))
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }

    private func submitButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if account.busy {
                    ProgressView().tint(palette.background)
                }
                Text(palette.style.label(title))
                    .font(palette.mono(15, .bold, relativeTo: .body))
                    .tracking(palette.style.labelTracking)
            }
            .foregroundStyle(palette.background)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.accent.opacity(account.busy ? 0.6 : 1), in: .rect(cornerRadius: palette.style.radius(6)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(account.busy)
    }

    // MARK: Actions

    private func sendCode() {
        Feedback.play(.tap)
        focused = nil
        let email = email
        let mode = mode
        Task {
            await account.sendCode(email: email, mode: mode)
            if account.pendingEmail != nil { focused = .code }
        }
    }

    private func verify() {
        Feedback.play(.tap)
        let code = code
        Task {
            await account.verify(code: code)
            if account.messageIsError { self.code = "" }
        }
    }
}
