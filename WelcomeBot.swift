#!/usr/bin/env swift

import Foundation

struct MastodonAccount: Codable {
    let id: String
    let username: String
    let createdAt: String
    let approved: Bool

    private enum CodingKeys: String, CodingKey {
        case id, username, approved
        case createdAt = "created_at"
    }
}

struct StatusRequest: Codable {
    let status: String
    let visibility: String
}

class MastodonWelcomeBot {
    private let baseURL: String
    private let accessToken: String
    private let timestampFile = "last_check_timestamp.txt"
    private let dateFormatter: ISO8601DateFormatter

    init() {
        // Try to load from .env file if it exists (for local development)
        Self.loadEnvFile()

        // Configure ISO8601 date formatter with more flexible options
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let baseURL = ProcessInfo.processInfo.environment["MASTODON_BASE_URL"],
              let accessToken = ProcessInfo.processInfo.environment["MASTODON_ACCESS_TOKEN"] else {
            fatalError("Missing required environment variables: MASTODON_BASE_URL, MASTODON_ACCESS_TOKEN")
        }

        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessToken = accessToken
    }

    private static func loadEnvFile() {
        guard let envData = try? String(contentsOfFile: ".env", encoding: .utf8) else {
            return // No .env file found, continue with system environment variables
        }

        let lines = envData.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue // Skip empty lines and comments
            }

            let parts = trimmed.components(separatedBy: "=")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                setenv(key, value, 1) // Add to environment
            }
        }
    }

    func run() async {
        do {
            let lastCheckTime = readLastCheckTime()
            print("Checking for new accounts since: \(lastCheckTime)")

            let newAccounts = try await fetchNewAccounts(since: lastCheckTime)
            print("Found \(newAccounts.count) new accounts")

            for account in newAccounts {
                try await sendWelcomeMessage(to: account)
                print("Sent welcome message to @\(account.username)")

                // Update timestamp after each successful send
                try updateLastProcessedAccount(to: account.createdAt)
                print("Updated timestamp to: \(account.createdAt)")

                // Small delay to be respectful of rate limits
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }

            print("Completed processing all new accounts")

        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    private func readLastCheckTime() -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: timestampFile)),
              let timestamp = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            // Default to 24 hours ago if no timestamp file exists
            let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            return dateFormatter.string(from: oneDayAgo)
        }
        print("Read timestamp from file: \(timestamp)")
        return timestamp
    }

    private func updateLastProcessedAccount(to timestamp: String) throws {
        try timestamp.write(to: URL(fileURLWithPath: timestampFile), atomically: true, encoding: .utf8)
    }

    private func fetchNewAccounts(since: String) async throws -> [MastodonAccount] {
        let url = URL(string: "\(baseURL)/api/v1/admin/accounts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "API", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch accounts"])
        }

        let allAccounts = try JSONDecoder().decode([MastodonAccount].self, from: data)

        // Filter for accounts created after our last check and are approved
        let sinceDate = dateFormatter.date(from: since) ?? {
            // Try fallback parsing without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            let fallbackDate = fallbackFormatter.date(from: since)
            print("Primary date parsing failed for '\(since)', fallback result: \(fallbackDate?.description ?? "nil")")
            return fallbackDate ?? Date.distantPast
        }()

        print("Found \(allAccounts.count) total accounts")
        print("Parsed since date '\(since)' as: \(sinceDate)")

        let newAccounts = allAccounts.filter { account in
            guard account.approved else { return false }

            if let accountDate = dateFormatter.date(from: account.createdAt) {
                let isNewer = accountDate > sinceDate
                if isNewer {
                    print("Account @\(account.username) created at \(account.createdAt) (\(accountDate)) is newer than \(sinceDate)")
                }
                return isNewer
            }
            return false
        }

        return newAccounts
    }

    private func sendWelcomeMessage(to account: MastodonAccount) async throws {
        let welcomeText = """
        @\(account.username) Welcome to the iOS Dev Space! 👋 if you have any issues with the server, let me know and the admin team can take a look at it

        Make sure to checkout the rules ➡️ https://iosdev.space/about

        Consider making a donation to cover maintenance costs of the instance ➡️ https://opencollective.com/iosdevspace. Even $1/month will help us keep the server running smoothly.

        Make sure to post and introduce yourself using #introduction

        Thanks for being here!
        """

        let statusRequest = StatusRequest(
            status: welcomeText,
            visibility: "direct"
        )

        let url = URL(string: "\(baseURL)/api/v1/statuses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONEncoder().encode(statusRequest)
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "API", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to send welcome message to @\(account.username)"])
        }
    }
}

// Main execution
let bot = MastodonWelcomeBot()
await bot.run()
