import Foundation
import Testing
@testable import FocusTimer

struct OnboardingGateTests {
    /// A throwaway defaults domain, removed after the test body runs.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "onboarding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func showsForBrandNewInstall() {
        withDefaults { defaults in
            #expect(OnboardingGate.shouldShow(defaults: defaults, taskCount: 0))
        }
    }

    @Test func emptyFontSettingStillCountsAsNew() {
        // `FontChoices.migrate()` writes "" on every launch.
        withDefaults { defaults in
            defaults.set("", forKey: FontChoices.key)
            #expect(OnboardingGate.shouldShow(defaults: defaults, taskCount: 0))
        }
    }

    @Test func hiddenOnceDone() {
        withDefaults { defaults in
            defaults.set(true, forKey: OnboardingGate.key)
            #expect(!OnboardingGate.shouldShow(defaults: defaults, taskCount: 0))
        }
    }

    @Test func hiddenWhenStyleWasChosen() {
        withDefaults { defaults in
            defaults.set("cozy", forKey: "terminalStyle")
            #expect(!OnboardingGate.shouldShow(defaults: defaults, taskCount: 0))
        }
    }

    @Test(arguments: ["focusMinutes", "restMinutes"])
    func hiddenWhenTimerWasChanged(key: String) {
        withDefaults { defaults in
            defaults.set(30, forKey: key)
            #expect(!OnboardingGate.shouldShow(defaults: defaults, taskCount: 0))
        }
    }

    @Test func hiddenWhenAFontWasChosen() {
        withDefaults { defaults in
            defaults.set("cozy=vt323", forKey: FontChoices.key)
            #expect(!OnboardingGate.shouldShow(defaults: defaults, taskCount: 0))
        }
    }

    @Test func hiddenWhenThereAreTasks() {
        withDefaults { defaults in
            #expect(!OnboardingGate.shouldShow(defaults: defaults, taskCount: 3))
        }
    }
}

struct AccountValidationTests {
    @Test func acceptsAGoodEmail() {
        #expect(AccountService.validate(email: "me@example.com") == nil)
    }

    @Test func trimsAndIgnoresCase() {
        #expect(AccountService.validate(email: "  Me@Example.COM \n") == nil)
        #expect(AccountService.clean("  Me@Example.COM ") == "me@example.com")
    }

    @Test(arguments: ["", "   ", "me", "me@", "@example.com", "me@example", "me@@example.com", "me@.com", "me@example.", "m e@example.com"])
    func rejectsBadEmails(email: String) {
        #expect(AccountService.validate(email: email) != nil)
    }

    @Test func acceptsSixDigitCodes() {
        #expect(AccountService.validate(code: "123456") == nil)
        #expect(AccountService.validate(code: "000000") == nil)
    }

    @Test(arguments: ["", "12345", "1234567", "12a456", "12 456", "١٢٣٤٥٦"])
    func rejectsOtherCodes(code: String) {
        #expect(AccountService.validate(code: code) == "the code is 6 digits")
    }

    @Test func explainsCommonAuthErrors() {
        #expect(AccountService.explain(text: "api(message: \"Token has expired or is invalid\", errorCode: otp_expired)").contains("code"))
        #expect(AccountService.explain(text: "Signups not allowed for otp").contains("create one"))
        #expect(AccountService.explain(text: "errorCode: email_exists").contains("log in"))
        #expect(AccountService.explain(text: "User already registered").contains("log in"))
        #expect(AccountService.explain(text: "over_email_send_rate_limit").contains("too many"))
        #expect(AccountService.explain(URLError(.notConnectedToInternet)).contains("offline"))
    }

    @MainActor @Test func noCooldownBeforeAnyCode() {
        let service = AccountService(sync: nil, defaults: UserDefaults(suiteName: "AccountTests.\(UUID())")!)
        #expect(service.resendWait() == 0)
    }
}
