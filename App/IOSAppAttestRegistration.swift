import CryptoKit
import DeviceCheck
import Foundation
import NordicSportsShared
import UIKit

// PRIVACY-SYNC: Sends the App Attest key proof and app/OS version to the Nordic Sports server to create or renew an anonymous installation account. No athlete data. Re-check design/privacy-notice-sync.md before enabling.
/// The first registration happens only during the server move, with its ticket
/// (registerWithTicket; design/server-migration.md in the Companion); registerIfDue at app
/// start only renews an install credential that exists.
@MainActor
final class IOSAppAttestRegistration {
    static let shared = IOSAppAttestRegistration()

    private let baseURL = URL(string: AppConfig.apiBaseUrl)!
    private let renewalIntervalMillis: Int64 = 23 * 24 * 60 * 60 * 1000
    private let retryIntervalMillis: Int64 = 6 * 60 * 60 * 1000

    private init() {}

    /// True when this build can register with App Attest (enabled in Info.plist, device supports it).
    static var available: Bool { enabled && DCAppAttestService.shared.isSupported }

    /// Renews the install credential when due; never registers a new install (that is the move's job).
    func registerIfDue(core: CompanionCore, log: (String) -> Void) async {
        guard Self.available, core.serverTokenKind == "install" else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let registeredAt = core.serverInstallRegisteredAtMillis()
        let lastAttemptAt = core.serverInstallRegistrationAttemptAtMillis()
        if registeredAt > 0, now - registeredAt < renewalIntervalMillis { return }
        if lastAttemptAt > 0, now - lastAttemptAt < retryIntervalMillis { return }

        core.markServerInstallRegistrationAttempt(atMillis: now)
        do {
            try await register(core: core)
        } catch let error as RegistrationError {
            log("App Attest registration failed (\(error.logCode))")
        } catch {
            log("App Attest registration failed (unexpected error)")
        }
    }

    /// The first registration of this install, with the server move's ticket: a new App Attest key,
    /// attested. True when the install credential is stored.
    func registerWithTicket(core: CompanionCore, ticket: String, log: (String) -> Void) async -> Bool {
        guard Self.available else { return false }
        guard
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            !appVersion.isEmpty,
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            !buildVersion.isEmpty
        else {
            log("App Attest registration with ticket failed (configuration)")
            return false
        }
        core.markServerInstallRegistrationAttempt(atMillis: Int64(Date().timeIntervalSince1970 * 1000))
        do {
            try await createAndSubmitAttestation(core: core, appVersion: appVersion, buildVersion: buildVersion, ticket: ticket)
            return true
        } catch let error as RegistrationError {
            log("App Attest registration with ticket failed (\(error.logCode))")
        } catch {
            log("App Attest registration with ticket failed (unexpected error)")
        }
        return false
    }

    private func register(core: CompanionCore) async throws {
        guard
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            !appVersion.isEmpty,
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            !buildVersion.isEmpty
        else {
            throw RegistrationError.invalidConfiguration
        }

        // Renewal only: a lost key cannot register again without a new ticket from the move.
        guard let keyId = core.serverAppAttestKeyId() else { throw RegistrationError.missingInstallationKey }
        try await submitAssertion(core: core, keyId: keyId, appVersion: appVersion, buildVersion: buildVersion)
    }

    private func createAndSubmitAttestation(core: CompanionCore, appVersion: String, buildVersion: String, ticket: String) async throws {
        let challenge = try await requestChallenge()
        let keyId = try await generateKey()
        guard core.saveServerAppAttestKeyId(keyId: keyId) else {
            throw RegistrationError.invalidKeyIdentifier
        }
        let attestation = try await attest(keyId: keyId, challenge: challenge)
        let answer = try await submit(
            body: [
                "challenge": challenge,
                "key_id": keyId,
                "attestation": attestation.base64EncodedString(),
                "app_version": appVersion,
                "build_version": buildVersion,
                "os_version": UIDevice.current.systemVersion,
                "registration_ticket": ticket,
            ],
            bearer: nil
        )
        try save(answer, core: core, keyId: keyId)
    }

    private func submitAssertion(core: CompanionCore, keyId: String, appVersion: String, buildVersion: String) async throws {
        let challenge = try await requestChallenge()
        let assertion = try await generateAssertion(keyId: keyId, challenge: challenge)
        let answer = try await submit(
            body: [
                "challenge": challenge,
                "key_id": keyId,
                "assertion": assertion.base64EncodedString(),
                "app_version": appVersion,
                "build_version": buildVersion,
                "os_version": UIDevice.current.systemVersion,
            ],
            bearer: core.serverInstallToken()
        )
        try save(answer, core: core, keyId: keyId)
    }

    private func requestChallenge() async throws -> String {
        let data = try await send(path: "/api/attest/challenge.php", method: "GET", body: nil, bearer: nil)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challenge = object["challenge"] as? String,
            challenge.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
        else {
            throw RegistrationError.invalidServerResponse
        }
        return challenge
    }

    private func submit(body: [String: String], bearer: String?) async throws -> [String: Any] {
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw RegistrationError.invalidRequest
        }
        let data = try await send(path: "/api/attest/register-ios.php", method: "POST", body: bodyData, bearer: bearer)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistrationError.invalidServerResponse
        }
        return object
    }

    private func send(path: String, method: String, body: Data?, bearer: String?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw RegistrationError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RegistrationError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw RegistrationError.invalidServerResponse
        }
        if http.statusCode == 409,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["code"] as? String == "key_not_registered" {
            throw RegistrationError.keyNotRegistered
        }
        guard (200...299).contains(http.statusCode) else {
            throw RegistrationError.serverRejected(http.statusCode)
        }
        return data
    }

    private func save(_ answer: [String: Any], core: CompanionCore, keyId: String) throws {
        guard
            answer["account_type"] as? String == "anonymous",
            let token = answer["install_token"] as? String,
            let userId = answer["user_id"] as? String,
            let installationId = answer["installation_id"] as? String
        else {
            throw RegistrationError.invalidServerResponse
        }
        let registeredAt = Int64(Date().timeIntervalSince1970 * 1000)
        guard core.saveAttestedServerRegistration(
            token: token,
            userId: userId,
            installationId: installationId,
            registeredAtMillis: registeredAt,
            appAttestKeyId: keyId
        ) else {
            throw RegistrationError.invalidServerResponse
        }
    }

    private func clientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    private func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DCAppAttestService.shared.generateKey { keyId, error in
                if error != nil {
                    continuation.resume(throwing: RegistrationError.attestationService)
                } else if let keyId, !keyId.isEmpty {
                    continuation.resume(returning: keyId)
                } else {
                    continuation.resume(throwing: RegistrationError.attestationService)
                }
            }
        }
    }

    private func attest(keyId: String, challenge: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash(challenge)) { object, error in
                if error != nil {
                    continuation.resume(throwing: RegistrationError.attestationService)
                } else if let object {
                    continuation.resume(returning: object)
                } else {
                    continuation.resume(throwing: RegistrationError.attestationService)
                }
            }
        }
    }

    private func generateAssertion(keyId: String, challenge: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash(challenge)) { assertion, error in
                if error != nil {
                    continuation.resume(throwing: RegistrationError.attestationService)
                } else if let assertion {
                    continuation.resume(returning: assertion)
                } else {
                    continuation.resume(throwing: RegistrationError.attestationService)
                }
            }
        }
    }

    private static var enabled: Bool {
        let value = Bundle.main.infoDictionary?["AppAttestRegistrationEnabled"]
        if let boolValue = value as? Bool { return boolValue }
        guard let stringValue = value as? String else { return false }
        return ["yes", "true", "1"].contains(stringValue.lowercased())
    }

    private enum RegistrationError: Error {
        case invalidConfiguration
        case invalidKeyIdentifier
        case invalidRequest
        case invalidServerResponse
        case keyNotRegistered
        case missingInstallationKey
        case network
        case attestationService
        case serverRejected(Int)

        var logCode: String {
            switch self {
            case .invalidConfiguration: return "configuration"
            case .invalidKeyIdentifier: return "key"
            case .invalidRequest: return "request"
            case .invalidServerResponse: return "response"
            case .keyNotRegistered: return "unregistered-key"
            case .missingInstallationKey: return "missing-key"
            case .network: return "network"
            case .attestationService: return "device-check"
            case .serverRejected(let status): return "server-\(status)"
            }
        }
    }
}

/// The shared core's store registration hook (CompanionCore.storeRegistration): the server move
/// hands its ticket here. Set only when App Attest is available, so other builds answer "later".
final class AppAttestStoreRegistration: NSObject, StoreRegistration {
    private let core: CompanionCore

    init(core: CompanionCore) {
        self.core = core
    }

    func register(ticket: String, done: @escaping (KotlinBoolean) -> Void) {
        Task { @MainActor in
            let ok = await IOSAppAttestRegistration.shared.registerWithTicket(core: core, ticket: ticket) { line in
                WatchLinkSpike.shared.add(line)
            }
            done(KotlinBoolean(bool: ok))
        }
    }
}
