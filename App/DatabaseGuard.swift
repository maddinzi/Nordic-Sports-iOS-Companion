import NordicSportsShared
import SwiftUI
import UIKit

/// The database on this iPhone was written by a newer build (an earlier TestFlight build installed over a newer one;
/// Kotlin `IosCompanion.databaseNewerThanApp`). Room has no way back there, so every query would fail. Read once at
/// launch, before anything creates `Companion.shared`: the app then shows only [DatabaseTooNewScreen] and never opens
/// the database. The watch link does not start (the watch keeps its activities until a newer build receives them),
/// background runs end at once and notification taps are ignored.
enum DatabaseGuard {
    static let tooNew: Bool = IosCompanion.shared.databaseNewerThanApp()
}

/// "Please update the app": the only screen while [DatabaseGuard.tooNew].
struct DatabaseTooNewScreen: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "arrow.down.app")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L10n.get("ios_database_too_new_title"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(L10n.get("ios_database_too_new_body"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            // TestFlight's own scheme: opens the app, where the newest build is one tap away.
            if let url = URL(string: "itms-beta://") {
                Button(L10n.get("ios_database_too_new_button")) { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
