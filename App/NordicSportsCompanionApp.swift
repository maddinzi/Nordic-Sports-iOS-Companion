import SwiftUI

/// First TestFlight build: proves the remote build, signing and upload chain. The watch
/// link spike (roadmap step 1) and the shared Kotlin module come next.
@main
struct NordicSportsCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(name) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.skiing.crosscountry")
                .font(.system(size: 64))
            Text("Nordic Sports Companion")
                .font(.title2.bold())
            Text("iOS preview build \(version)")
                .foregroundStyle(.secondary)
            Text("Built in the cloud and delivered via TestFlight. The watch link comes next.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}
