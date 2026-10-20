#!/usr/bin/env python3
"""Generate the iOS String Catalog from the Android Companion's texts.

Decision (docs/decision-shared-texts.md, option A): the Android `strings.xml` and
`watch_labels.xml` in the Companion repo are the only source of every text in all six
languages. This script turns them into `Localizable.xcstrings`, which Xcode compiles into
the app; Swift reads a text by its Android name: `String(localized: "status_title")`.
The Android completeness test (TranslationCompletenessTest) keeps guarding the source.

    python3 tools/generate_strings.py <companion>/app/src/main/res App/Localizable.xcstrings [App/Texts]

With a third argument it also writes one text table per language, `<dir>/texts-<lang>.json`
(name -> text, or plural form -> text), in Android's own format syntax (`%1$s`, `%d`), with
English filled in for names a language lacks. The shared Kotlin code reads these
(`StringTable`), so the log and worklog lines the shared logic writes read as on Android.

Conversions: `%1$s` -> `%1$@` (Swift strings are objects), `%1$d` -> `%1$lld` (Kotlin Int
and Swift Int are 64 bit on iOS), floats unchanged; Android escapes (`\\'`, `\\"`, `\\n`) are
resolved; `<plurals>` become plural variations. A name marked translatable="false" exists in
English only and is marked as not to be translated.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Android resource folder -> iOS language code.
LANGUAGES = {
    "values": "en",
    "values-de": "de",
    "values-fr": "fr",
    "values-it": "it",
    "values-rm": "rm",
    "values-b+gsw": "gsw",
    "values-nb": "nb",
    "values-fi": "fi",
    "values-sv": "sv",
}
FILES = ["strings.xml", "watch_labels.xml"]
PLURAL_FORMS = {"zero", "one", "two", "few", "many", "other"}

_FORMAT = re.compile(r"%(\d+\$)?([-+ 0#]*\d*(?:\.\d+)?)([sdf%])")


def convert_format(text: str) -> str:
    """Android/Java format specifiers to the ones Foundation's String(format:) expects."""
    def repl(m):
        position, flags, kind = m.group(1) or "", m.group(2), m.group(3)
        if kind == "%":
            return "%%"
        if kind == "s":
            return f"%{position}{flags}@"
        if kind == "d":
            return f"%{position}{flags}lld"
        return m.group(0)
    return _FORMAT.sub(repl, text)


def unescape(raw: str) -> str:
    """Android string resource escapes, after XML entities are resolved by the parser.
    Like Android, runs of whitespace in the source collapse to one space and the ends are
    trimmed; an escaped `\\n` is a real line break."""
    raw = re.sub(r"\s+", " ", raw).strip()
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            out.append({"n": "\n", "t": "\t", "'": "'", '"': '"', "\\": "\\", "@": "@", "?": "?"}.get(n, n))
            i += 2
            continue
        if c == '"':  # unescaped quotes only group text in Android; they are not shown
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def text_of(element, android_format: bool = False) -> str:
    text = unescape("".join(element.itertext()))
    return text if android_format else convert_format(text)


def read_language(folder: Path, android_format: bool = False):
    """name -> str or {plural form: str}, plus the names marked translatable="false"."""
    texts, fixed = {}, set()
    for name in FILES:
        path = folder / name
        if not path.exists():
            continue
        for el in ET.parse(path).getroot():
            key = el.get("name")
            if el.tag == "string":
                texts[key] = text_of(el, android_format)
            elif el.tag == "string-array":
                # iOS has no arrays: item i is the text "<name>_<i>".
                for index, item in enumerate(el.findall("item")):
                    texts[f"{key}_{index}"] = text_of(item, android_format)
                    if el.get("translatable") == "false":
                        fixed.add(f"{key}_{index}")
                continue
            elif el.tag == "plurals":
                forms = {item.get("quantity"): text_of(item, android_format) for item in el if item.get("quantity") in PLURAL_FORMS}
                texts[key] = forms
            else:
                continue
            if el.get("translatable") == "false":
                fixed.add(key)
    return texts, fixed


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value) -> dict:
    if isinstance(value, dict):
        return {"variations": {"plural": {form: unit(v) for form, v in sorted(value.items())}}}
    return unit(value)


def build_catalog(res: Path) -> dict:
    per_language = {lang: read_language(res / folder) for folder, lang in LANGUAGES.items()}
    english, fixed = per_language["en"]
    strings = {}
    for key in sorted(english):
        entry = {"extractionState": "manual", "localizations": {"en": localization(english[key])}}
        if key in fixed:
            entry["shouldTranslate"] = False
        else:
            for lang, (texts, _) in per_language.items():
                if lang != "en" and key in texts:
                    entry["localizations"][lang] = localization(texts[key])
        strings[key] = entry
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def build_tables(res: Path) -> dict:
    """language -> {name: text or {plural form: text}} in Android format, English filled in."""
    english, _ = read_language(res / "values", android_format=True)
    tables = {}
    for folder, lang in LANGUAGES.items():
        texts, _ = read_language(res / folder, android_format=True)
        tables[lang] = {**english, **texts}
    return tables


def _placeholders(text: str) -> list:
    """The format conversions in a text, sorted: a translation must take the same arguments as the
    English text, or String(format:) reads the wrong memory."""
    return sorted(m[2] for m in _FORMAT.findall(text) if m[2] != "%")


def placeholder_problems(res: Path) -> list:
    """Names whose translation has other format placeholders than the English text."""
    english, _ = read_language(res / "values", android_format=True)
    problems = []
    for folder, lang in LANGUAGES.items():
        if lang == "en":
            continue
        texts, _ = read_language(res / folder, android_format=True)
        for key, value in texts.items():
            if key not in english:
                continue
            if isinstance(value, dict) != isinstance(english[key], dict):
                problems.append(f"{lang}/{key}: plural and plain text mixed")
            elif isinstance(value, str) and _placeholders(value) != _placeholders(english[key]):
                problems.append(f"{lang}/{key}: placeholders {_placeholders(value)} instead of {_placeholders(english[key])}")
    return problems


def main(argv):
    if len(argv) not in (3, 4):
        sys.exit(__doc__)
    res, out = Path(argv[1]), Path(argv[2])
    problems = placeholder_problems(res)
    if problems:
        sys.exit("Format placeholders differ from the English text:\n  " + "\n  ".join(problems))
    if len(argv) == 4:
        folder = Path(argv[3])
        folder.mkdir(parents=True, exist_ok=True)
        for lang, table in build_tables(res).items():
            (folder / f"texts-{lang}.json").write_text(json.dumps(table, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        print(f"{folder}: {len(LANGUAGES)} text tables")
    catalog = build_catalog(res)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    counts = {lang: sum(1 for e in catalog["strings"].values() if lang in e["localizations"]) for lang in LANGUAGES.values()}
    print(f"{out}: {len(catalog['strings'])} texts; per language: {counts}")


if __name__ == "__main__":
    main(sys.argv)
