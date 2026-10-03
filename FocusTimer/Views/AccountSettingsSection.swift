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
            } else if account.needsPassword {
                LabeledContent("account", value: account.email ?? account.pendingEmail ?? "?")
                AccountForm(palette: palette)
            } else if account.isGuest {
                LabeledContent("account", value: "guest")
                if showForm || account.pendingEmail != nil {
                    AccountForm(palette: palette)
                } else {
                    Button {
                        Feedback.play(.tap)
                        account.clearMessage()
                        withAnimation(.easeInOut(duration: 0.25)) { showForm = true }
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
            Text("As a guest, tasks live on this iPhone and only this install can reach its backup. With an account, they sync to every iPhone and iPad running Focus. Signing out keeps your tasks here.")
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
            Text("Your tasks stay on this iPhone. Log in again any time to sync.")
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

/// Create an account or log in: email, password, submit. Used in Settings and in the setup guide.
struct AccountForm: View {
    let palette: Palette

    enum Mode: String, CaseIterable, Identifiable {
        case create, logIn

        var id: String { rawValue }
        var label: String { self == .create ? "create account" : "log in" }
    }

    @State private var mode: Mode = .create
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var account: AccountService { AccountService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if account.needsPassword {
                finishSetup
            } else {
                if let pending = account.pendingEmail, account.isGuest {
                    pendingNotice(pending)
                }
                Picker("account", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                field {
                    TextField("email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .password }
                }
                field {
                    SecureField("password (8+ characters)", text: $password)
                        .textContentType(mode == .create ? .newPassword : .password)
                        .submitLabel(.go)
                        .focused($focused, equals: .password)
                        .onSubmit(submit)
                }
                submitButton(mode.label, action: submit)
            }
            if let message = account.message {
                Text(message)
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(account.messageIsError ? Color(hex: 0xE0786A) : palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("sync works on every iPhone and iPad running Focus.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .font(palette.mono(15, relativeTo: .body))
        .padding(.vertical, 4)
        .onChange(of: mode) {
            Feedback.play(.tap)
            account.clearMessage()
        }
    }

    // MARK: Pieces

    private var finishSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("email confirmed. choose your password to finish.")
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            field {
                SecureField("password (8+ characters)", text: $password)
                    .textContentType(.newPassword)
                    .submitLabel(.go)
                    .onSubmit(setPassword)
            }
            submitButton("set password", action: setPassword)
        }
    }

    private func pendingNotice(_ pending: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("waiting for you to confirm \(pending). open the link in that email, then tap below.")
                .font(palette.mono(13, relativeTo: .footnote))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Feedback.play(.tap)
                Task { await account.refresh() }
            } label: {
                Label("i confirmed it", systemImage: "checkmark.circle")
                    .font(palette.mono(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
            .disabled(account.busy)
        }
    }

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

    private func submit() {
        Feedback.play(.tap)
        focused = nil
        let email = email
        let password = password
        Task {
            switch mode {
            case .create: await account.createAccount(email: email, password: password)
            case .logIn: await account.logIn(email: email, password: password)
            }
            if !account.messageIsError { self.password = "" }
        }
    }

    private func setPassword() {
        Feedback.play(.tap)
        let password = password
        Task {
            await account.setPassword(password)
            if !account.messageIsError { self.password = "" }
        }
    }
}
