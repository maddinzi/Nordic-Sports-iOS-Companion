import SwiftUI

/// "Record on my watch" (Android `WatchRecordStartScreen`): the phone cannot start the watch app, so this says step by
/// step how to start on the watch. iOS shows the steps only; the watch settings are not editable on iOS yet.
struct WatchRecordStartView: View {
    @Environment(\.dismiss) private var dismiss
    private let tone = CardTone.blue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.get("watch_start_steps_title")).font(.title3.weight(.semibold)).foregroundStyle(tone.title)
                    ForEach(1...8, id: \.self) { n in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(n)").font(.subheadline.bold()).foregroundStyle(tone.container)
                                .frame(width: 26, height: 26).background(tone.title, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.get("watch_start_step\(n)_title")).font(.subheadline.weight(.semibold))
                                Text(L10n.get("watch_start_step\(n)_body")).font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
                .background(tone.container, in: RoundedRectangle(cornerRadius: 14))
                .padding(16)
            }
            .navigationTitle(L10n.get("add_choice_watch_title"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text(L10n.get("watch_start_done")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
                .background(.bar)
            }
        }
    }
}
