import Foundation
import Supabase

/// Thin wrapper over the Supabase client: anonymous auth plus the two tables.
/// Row-level security scopes every query to the signed-in user.
final class SupabaseService: Sendable {
    let client: SupabaseClient

    init(url: URL, key: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    /// Reads SUPABASE_HOST / SUPABASE_ANON_KEY injected from Config/*.xcconfig.
    /// Returns nil (local-only mode) when they are not configured.
    static func fromInfoPlist(_ bundle: Bundle = .main) -> SupabaseService? {
        guard
            let host = bundle.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String,
            let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !host.isEmpty, !key.isEmpty, !host.contains("$("),
            let url = URL(string: "https://\(host)")
        else { return nil }
        return SupabaseService(url: url, key: key)
    }

    func ensureSignedIn() async throws {
        if (try? await client.auth.session) != nil { return }
        _ = try await client.auth.signInAnonymously()
    }

    /// The signed-in user as the server sees it now (picks up an email confirmed in the browser);
    /// nil when there is no session.
    func currentUser() async -> User? {
        guard (try? await client.auth.session) != nil else { return nil }
        if let fresh = try? await client.auth.user() { return fresh }
        return try? await client.auth.session.user
    }

    func upsertTasks(_ rows: [TaskDTO]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("tasks").upsert(rows).execute()
    }

    func fetchTasks(updatedAfter since: Date?) async throws -> [TaskDTO] {
        let query = client.from("tasks").select()
        let filtered = if let since { query.gt("updated_at", value: Self.timestamp(since)) } else { query }
        return try await filtered.order("updated_at").execute().value
    }

    func insertSessions(_ rows: [FocusSessionDTO]) async throws {
        guard !rows.isEmpty else { return }
        // Idempotent: a retry after a dropped response must not duplicate sessions.
        try await client.from("focus_sessions").upsert(rows, ignoreDuplicates: true).execute()
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
