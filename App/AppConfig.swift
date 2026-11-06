import Foundation

/// The app's server and website addresses, in one place for a domain move. The associated domains
/// (Strava's https sign-in return) are in project.yml and must name the same API host.
enum AppConfig {
    /// The webhook server: Strava sign-in callback (Universal Link), webhook API and App Attest.
    static let apiHost = "api.nordicsports.maddin.me"
    static let apiBaseUrl = "https://\(apiHost)"
    /// The website: privacy notice, imprint.
    static let websiteUrl = "https://nordicsports.maddin.me"
}
