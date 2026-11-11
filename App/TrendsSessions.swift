import NordicSportsShared
import SwiftUI

// The Trends "Sessions" theme (Android `TrendsGuided.kt`): guided interval sessions and strength per exercise, from the
// watch's follow-up tables and phone recordings alike. The numbers come from the shared `Trends`.

/// "10 Nov 2026" in the app's language.
private func sessionDate(_ epochSec: Int64) -> String {
    Date(timeIntervalSince1970: TimeInterval(epochSec)).formatted(date: .abbreviated, time: .omitted)
}

/// Pace for running, km/h otherwise.
private func sessionSpeed(_ mps: Double, family: String) -> String {
    if family == "RUNNING" {
        guard let pace = ActivityFigures.shared.paceSecPerKm(speedMps: Float(mps))?.int32Value else { return "–" }
        return ActivityFigures.shared.paceText(secPerKm: pace) + " /km"
    }
    return (mps * 3.6).formatted(.number.precision(.fractionLength(1))) + " km/h"
}

private func sessionClock(_ seconds: Int32) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

/// The guided interval sessions of the period, newest first: per session a bar per work rep (speed, or heart rate
/// where there is no speed), the averages and how the last rep compares to the first. A tap opens the activity.
struct TrendIntervalSessionsChart: View {
    let sessions: [TrendIntervalSession]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sessions.prefix(6)), id: \.id) { s in
                Button { onOpen(s.id) } label: { row(s) }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ s: TrendIntervalSession) -> some View {
        let work = L10n.get("watch_interval_work")
        let figures = [
            "\(s.reps) × \(work) Ø \(sessionClock(s.avgWorkSec))",
            s.avgSpeedMps.map { sessionSpeed($0.doubleValue, family: s.family) },
            s.avgHr.map { "\($0.intValue) bpm" },
        ].compactMap { $0 }.joined(separator: " · ")
        let change: (String, String)? = {
            guard s.reps > 1 else { return nil }
            if let a = s.firstSpeedMps, let b = s.lastSpeedMps {
                return (sessionSpeed(a.doubleValue, family: s.family), sessionSpeed(b.doubleValue, family: s.family))
            }
            if let a = s.firstHr, let b = s.lastHr { return ("\(a.intValue) bpm", "\(b.intValue) bpm") }
            return nil
        }()
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(sessionDate(s.startEpochSec)) · \(s.title)").font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(figures).font(.caption).foregroundStyle(.secondary)
            RepBars(session: s)
            if let change {
                Text(String(format: L10n.get("trends_int_first_last"), change.0, change.1)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// One bar per work rep: the slowest rep a third of the height, the fastest the full height (heart rate without speed).
private struct RepBars: View {
    let session: TrendIntervalSession

    var body: some View {
        let speeds = session.repSpeeds.map { $0.doubleValue }
        let values = speeds.contains { $0 > 0 } ? speeds : session.repHrs.map { Double($0.intValue) }
        let positive = values.filter { $0 > 0 }
        if let max = positive.max(), let min = positive.min() {
            let span = max - min > 0 ? max - min : 1
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    let f = v <= 0 ? 0.08 : 0.33 + 0.67 * (v - min) / span
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28 * f)
                }
            }
            .frame(height: 28, alignment: .bottom)
        }
    }
}

/// Where the training time went (Android `TrainingShareChart`): one bar split by training type, strength by its
/// purpose, then a line per slice with its time, share and sessions.
struct TrendTrainingShareChart: View {
    let shares: [TrendTrainingShare]
    private static let colours: [Color] = [
        Color(red: 0.12, green: 0.44, blue: 0.70), Color(red: 0.88, green: 0.48, blue: 0.22), Color(red: 0.24, green: 0.60, blue: 0.37),
        Color(red: 0.56, green: 0.36, blue: 0.71), Color(red: 0.79, green: 0.31, blue: 0.43), Color(red: 0.16, green: 0.65, blue: 0.63),
        Color(red: 0.61, green: 0.48, blue: 0.24),
    ]

    var body: some View {
        let total = max(1, shares.reduce(0) { $0 + Int($1.seconds) })
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { i, s in
                        Self.colours[i % Self.colours.count].frame(width: geo.size.width * CGFloat(s.seconds) / CGFloat(total))
                    }
                }
            }
            .frame(height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            ForEach(Array(shares.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Self.colours[i % Self.colours.count]).frame(width: 10, height: 10)
                    Text(label(s)).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("\(trendDuration(Int(s.seconds))) · \(Int((Double(s.seconds) * 100 / Double(total)).rounded())) % · \(s.sessions)×")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func label(_ s: TrendTrainingShare) -> String {
        let presetKey = "watch_preset_\(s.preset)"
        let preset = L10n.get(presetKey) == presetKey ? s.preset : L10n.get(presetKey)
        guard !s.trainingType.isEmpty else { return preset }
        let typeKey = "watch_training_type_\(s.trainingType)"
        return L10n.get(typeKey) == typeKey ? preset : "\(preset) · \(L10n.get(typeKey))"
    }
}

/// The most performed exercises (Android `TopExercisesChart`): a bar per exercise by sets, with reps or seconds and the
/// weight moved.
struct TrendTopExercisesChart: View {
    let top: [TrendTopExercise]

    var body: some View {
        let most = max(1, top.map { Int($0.sets) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(top, id: \.exercise) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(name(e.exercise)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if e.volumeKg > 0 {
                            Text("\(e.volumeKg.formatted(.number.precision(.fractionLength(0)))) kg").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(e.sets) / CGFloat(most))
                    }
                    .frame(height: 10)
                    Text(String(format: L10n.get(e.hold ? "trends_top_line_hold" : "trends_top_line"), Int(e.sets), Int(e.reps)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func name(_ exercise: String) -> String {
        let key = "watch_exercise_\(exercise)"
        let text = L10n.get(key)
        return text == key ? exercise : text
    }
}

/// A long list that starts closed (Android `CollapsedList`): a "Show" row with a chevron, the list once opened.
struct TrendCollapsedList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack {
                    Text(L10n.get(open ? "trends_hide" : "trends_show")).font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            if open { content() }
        }
    }
}

/// Strength per exercise over the period, by volume: per session the sets, reps or seconds, kg moved and the
/// heaviest set, newest first. A tap on a session opens the activity.
struct TrendStrengthExercisesChart: View {
    let exercises: [TrendExercise]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(exercises.prefix(6)), id: \.exercise) { e in
                let hold = StrengthCatalog.shared.HOLD_EXERCISES.contains(e.exercise)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(e.exercise)).font(.subheadline.weight(.semibold))
                    ForEach(Array(e.sessions.prefix(4)), id: \.id) { s in
                        Button { onOpen(s.id) } label: {
                            Text(line(s, hold: hold)).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func name(_ exercise: String) -> String {
        if exercise.isEmpty { return L10n.get("phone_guide_no_exercise") }
        let key = "watch_exercise_\(exercise)"
        let text = L10n.get(key)
        return text == key ? exercise : text
    }

    private func line(_ s: TrendExerciseSession, hold: Bool) -> String {
        let kg: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
        return [
            sessionDate(s.startEpochSec),
            "\(s.sets) × " + (hold ? "\(s.reps) s" : "\(s.reps)"),
            s.volumeKg > 0 ? "\(kg(s.volumeKg)) kg" : nil,
            s.bestKg > 0 ? String(format: L10n.get("trends_str_best"), kg(Double(s.bestKg))) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}
