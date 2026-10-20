import NordicSportsShared
import SwiftUI

// "Wording / translation" in the feedback form: search any text of the Companion or the watch
// in any language, pick it and propose a better wording. The index is the Companion's generated
// wording_texts.json (CI copies it into App/Texts); search and parsing are the shared
// WordingCatalog / WordingSearch, so Android and iOS rank alike.

enum WordingFeedback {
    static let languages = ["en", "de", "fr", "it", "gsw", "rm", "nb", "fi", "sv"]

    private static let flags = [
        "en": "\u{1F1EC}\u{1F1E7}", "de": "\u{1F1E9}\u{1F1EA}", "fr": "\u{1F1EB}\u{1F1F7}",
        "it": "\u{1F1EE}\u{1F1F9}", "gsw": "\u{1F1E8}\u{1F1ED}", "rm": "\u{1F1E8}\u{1F1ED}",
        "nb": "\u{1F1F3}\u{1F1F4}", "fi": "\u{1F1EB}\u{1F1EE}", "sv": "\u{1F1F8}\u{1F1EA}",
    ]

    /// Flag plus short code; Swiss German shows as CH (the code stays gsw in the data).
    static func label(_ code: String) -> String {
        let short = code == "gsw" ? "CH" : code.uppercased()
        if let flag = flags[code] { return "\(flag) \(short)" }
        return short
    }

    /// The entries of the bundled index, empty if the file is missing.
    static func load() -> [WordingEntry] {
        guard let url = Bundle.main.url(forResource: "wording_texts", withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return WordingCatalog.shared.parse(json: json)
    }

    /// The message (plain English, for the admin list) and the wording_* details.
    static func compose(entry: WordingEntry, lang: String, current: String, proposed: String, reason: String)
        -> (message: String, details: [String: String]) {
        var message = "Wording suggestion for \(entry.id) (\(lang))\nCurrent: \(current)\nProposed: \(proposed)"
        if !reason.isEmpty { message += "\nReason: \(reason)" }
        var details = [
            "wording_key": entry.id,
            "wording_lang": lang,
            "wording_current": String(current.prefix(500)),
            "wording_proposed": String(proposed.prefix(500)),
        ]
        if !reason.isEmpty { details["wording_reason"] = String(reason.prefix(500)) }
        return (String(message.prefix(4000)), details)
    }
}

/// Search field and hit list, then the picked text with language chips and the proposal field.
struct WordingPicker: View {
    let entries: [WordingEntry]
    let appLanguage: String
    @Binding var picked: WordingEntry?
    @Binding var lang: String
    @Binding var proposed: String
    @State private var query = ""

    private var shownLang: String { WordingFeedback.languages.contains(appLanguage) ? appLanguage : "en" }

    var body: some View {
        if let entry = picked {
            Section(L10n.get("feedback_wording_current")) {
                Text("\(entry.app == .watch ? L10n.get("feedback_app_watch") : L10n.get("feedback_app_companion")) · \(entry.name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("", selection: $lang) {
                    ForEach(WordingFeedback.languages, id: \.self) { code in
                        Text(WordingFeedback.label(code)).tag(code)
                    }
                }
                .pickerStyle(.menu)
                Text(entry.texts[lang] ?? "\u{2013}")
                TextField(String(format: L10n.get("feedback_wording_proposed"), WordingFeedback.label(lang)),
                          text: $proposed, axis: .vertical)
                    .lineLimit(2...6)
                Button(L10n.get("feedback_wording_change")) {
                    picked = nil
                    proposed = ""
                }
            }
        } else {
            Section {
                TextField(L10n.get("feedback_wording_search"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(L10n.get("feedback_wording_search_hint")).font(.footnote).foregroundStyle(.secondary)
                let hits = query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? [] : WordingSearch.shared.search(entries: entries, query: query, preferredLanguage: shownLang, limit: 30)
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && hits.isEmpty {
                    Text(L10n.get("feedback_wording_no_hits")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(hits, id: \.id) { hit in
                    Button {
                        picked = hit
                        lang = shownLang
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.texts[shownLang] ?? hit.texts["en"] ?? "").foregroundStyle(.primary)
                            let english = shownLang != "en" && hit.texts["en"] != hit.texts[shownLang] ? hit.texts["en"] : nil
                            let where_ = hit.app == .watch ? L10n.get("feedback_app_watch") : L10n.get("feedback_app_companion")
                            Text([where_, english, hit.name].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
