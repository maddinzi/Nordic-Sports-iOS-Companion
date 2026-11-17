import NordicSportsShared
import SwiftUI

/// "Nordic Sports GO", the simple start screen (Companion repo, design/simple-and-expert-mode.md, sections 8b and 8c;
/// Android `GoHomeScreen`): one large Record tile, the last activity and the distance of the last 7 days, and above
/// them only what must not get lost (one status line, the running recordings). Activities and Trends are tabs.
struct GoScreen: View {
    @EnvironmentObject var companion: Companion
    /// The status line leads to the activity list; the gear opens Settings (the tabs live in the root view).
    let onShowList: () -> Void
    let onShowTrends: () -> Void
    let onShowSettings: () -> Void

    @State private var choosing = false
    @State private var adding = false
    @State private var recordStart = false
    @State private var watchHelp = false
    @State private var recordLive = false
    @State private var route: ActivityRoute?
    @State private var burstRoute: BurstRoute?
    @State private var week: [FamilyDistance] = []

    /// Activities still to declare (as the list's "open" section); none while new activities are not reviewed.
    private var toReview: Int {
        guard companion.reviewNewActivities else { return 0 }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return companion.activities.filter { $0.reviewPending && now < $0.reviewDeadlineEpochMillis }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // The busy line while the app syncs, then its plain result (plan sections 7 and 8b, point 5).
                    BusyBanner()
                    statusLine
                    ForEach(companion.liveActivities, id: \.deviceId) { live in
                        WatchLiveCard(live: live) { burstRoute = BurstRoute(id: $0) }
                            .padding(14)
                            .background(CardTone.red.container, in: RoundedRectangle(cornerRadius: 14))
                    }
                    recordTile
                    if let last = companion.activities.max(by: { $0.startEpochSec < $1.startEpochSec }) {
                        Text(L10n.get("go_last_activity"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        ActivityCard(item: last, stravaConnected: companion.stravaConnected, diaryConnected: companion.diaryReceives) {
                            route = ActivityRoute(id: last.id, target: $0)
                        }
                        .padding(14)
                        .background(CardTone.blue.container, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if !week.isEmpty { weekCard }
                    NavigationLink(L10n.get("go_about")) { AboutScreen() }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle(L10n.get("go_title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $route) { route in
                ActivityRouteView(id: route.id, target: route.target, pick: route.pick)
            }
            .navigationDestination(item: $burstRoute) { route in
                SensorRecordView(burstId: route.id, showUpload: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { FeedbackHubScreen() } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel(L10n.get("go_feedback_content_description"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onShowSettings) { Image(systemName: "gearshape") }
                        .accessibilityLabel(L10n.get("go_settings_content_description"))
                }
            }
            .task(id: companion.activities.count) { week = await companion.weekDistance() }
            .onAppear { companion.refreshWatchCards() }
            .sheet(isPresented: $adding) { AddActivitySheet().environmentObject(companion) }
            // The same choice as the list's "+" (Android: one menu, two entry points).
            .confirmationDialog(L10n.get("add_activity_title"), isPresented: $choosing, titleVisibility: .visible) {
                Button(L10n.get("add_choice_watch")) { watchHelp = true }
                Button(L10n.get("add_choice_record")) { recordStart = true }
                Button(L10n.get("add_choice_enter")) { adding = true }
                Button(L10n.get("common_cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $watchHelp) { WatchRecordStartView().environmentObject(companion) }
            .sheet(isPresented: $recordStart) {
                PhoneRecordStartScreen(phone: companion.phone) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { recordLive = true }
                }
                .environmentObject(companion)
            }
            .fullScreenCover(isPresented: $recordLive) {
                PhoneRecordingLiveScreen(phone: companion.phone) { id in route = ActivityRoute(id: id) }
                    .environmentObject(companion)
            }
        }
    }

    /// One line: problems orange, else activities to review yellow, else nothing (plan section 8b, point 6).
    @ViewBuilder private var statusLine: some View {
        let problems = Int(companion.syncStatus?.total ?? 0)
        let review = toReview
        if problems > 0 || review > 0 {
            let tone: CardTone = problems > 0 ? .orange : .yellow
            Button(action: onShowList) {
                Text(problems > 0
                     ? String(format: L10n.get("go_status_problem"), problems)
                     : String(format: L10n.get("go_status_review"), review))
                    .font(.headline)
                    .foregroundStyle(tone.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(tone.container, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    /// The large Record tile: the "+" choice, or back to a recording that runs on this phone.
    private var recordTile: some View {
        let running = companion.phone.view != nil
        return Button {
            if running { recordLive = true } else { choosing = true }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: running ? "record.circle" : "figure.skiing.crosscountry")
                    .font(.system(size: 44))
                    .foregroundStyle(running ? Color.red : Color.accentColor)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.get(running ? "add_choice_back_to_recording" : "go_tile_record"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(L10n.get("go_tile_record_body"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    /// Distance per sport over the last 7 days: one bar per sport in its Trends colour, the name and the km in text
    /// colours, so the colour is never the only label. A tap opens Trends.
    private var weekCard: some View {
        let max = Swift.max(week.map { Int($0.metres) }.max() ?? 1, 1)
        return Button(action: onShowTrends) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.get("go_week_distance")).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                ForEach(week, id: \.family) { row in
                    HStack(spacing: 8) {
                        Text(trendFamilyName(row.family))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 92, alignment: .leading)
                        GeometryReader { geo in
                            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 4, topTrailingRadius: 4)
                                .fill(trendGroupColor("\(row.family)|"))
                                .frame(width: geo.size.width * CGFloat(row.metres) / CGFloat(max), height: 12)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)
                        Text(String(format: "%.1f %@", Double(row.metres) / 1000, L10n.get("trends_unit_km")))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

/// The name of a Trends sport family ("XC" → "Cross-country skiing"), as the Trends screen shows it.
func trendFamilyName(_ f: String) -> String {
    switch f {
    case "ALL": return L10n.get("trends_family_all")
    case "XC": return L10n.get("trends_family_xc")
    case "ROLLSKI": return L10n.get("trends_family_rollski")
    case "RUNNING": return L10n.get("trends_family_running")
    case "INLINE": return L10n.get("trends_family_inline")
    case "WALK": return L10n.get("phone_family_walk")
    case "SWIM": return L10n.get("watch_preset_swim")
    case "STRENGTH": return L10n.get("trends_family_strength")
    case "MOBILITY": return L10n.get("trends_family_mobility")
    default: return L10n.get("trends_family_other")
    }
}
