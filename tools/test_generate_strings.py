"""Tests for generate_strings.py: python -m unittest discover tools"""
import tempfile
import unittest
from pathlib import Path

from generate_strings import build_catalog, build_tables, convert_format, placeholder_problems, unescape


class ConversionTest(unittest.TestCase):
    def test_formats(self):
        self.assertEqual("Sent to %1$@: %2$@", convert_format("Sent to %1$s: %2$s"))
        self.assertEqual("%1$lld of %2$lld", convert_format("%1$d of %2$d"))
        self.assertEqual("%@ and %lld", convert_format("%s and %d"))
        self.assertEqual("%1$.1f km, 100%%", convert_format("%1$.1f km, 100%%"))

    def test_android_escapes(self):
        self.assertEqual("Don't \"quote\"\nnext", unescape("Don\\'t \\\"quote\\\"\\nnext"))
        self.assertEqual("a b", unescape("  a\n      b  "))
        self.assertEqual("C:\\x", unescape("C:\\\\x"))


class ArrayTest(unittest.TestCase):
    def test_string_array_items_become_numbered_texts(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = Path(tmp)
            (res / "values").mkdir()
            (res / "values-de").mkdir()
            (res / "values" / "strings.xml").write_text(
                '<resources><string-array name="labels"><item>One</item><item>Two</item></string-array></resources>', encoding="utf-8")
            (res / "values-de" / "strings.xml").write_text(
                '<resources><string-array name="labels"><item>Eins</item><item>Zwei</item></string-array></resources>', encoding="utf-8")
            strings = build_catalog(res)["strings"]
        self.assertEqual({"labels_0", "labels_1"}, set(strings))
        self.assertEqual("Zwei", strings["labels_1"]["localizations"]["de"]["stringUnit"]["value"])


class CatalogTest(unittest.TestCase):
    def test_languages_plurals_and_fixed_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = Path(tmp)
            (res / "values").mkdir()
            (res / "values-de").mkdir()
            (res / "values" / "strings.xml").write_text(
                '<resources>'
                '<string name="hello">Hello %1$s &amp; you</string>'
                '<string name="brand" translatable="false">Strava</string>'
                '<plurals name="waiting"><item quantity="one">%d change</item><item quantity="other">%d changes</item></plurals>'
                '</resources>', encoding="utf-8")
            (res / "values-de" / "strings.xml").write_text(
                '<resources><string name="hello">Hallo %1$s &amp; du</string>'
                '<plurals name="waiting"><item quantity="one">%d Änderung</item><item quantity="other">%d Änderungen</item></plurals>'
                '</resources>', encoding="utf-8")
            catalog = build_catalog(res)

        strings = catalog["strings"]
        self.assertEqual("en", catalog["sourceLanguage"])
        self.assertEqual("Hello %1$@ & you", strings["hello"]["localizations"]["en"]["stringUnit"]["value"])
        self.assertEqual("Hallo %1$@ & du", strings["hello"]["localizations"]["de"]["stringUnit"]["value"])
        self.assertFalse(strings["brand"]["shouldTranslate"])
        self.assertEqual(["en"], list(strings["brand"]["localizations"]))
        plural = strings["waiting"]["localizations"]["de"]["variations"]["plural"]
        self.assertEqual("%lld Änderungen", plural["other"]["stringUnit"]["value"])
        self.assertEqual({"one", "other"}, set(plural))


class ReferenceTest(unittest.TestCase):
    def _res(self, tmp, english_extra=""):
        res = Path(tmp)
        (res / "values").mkdir()
        (res / "values-de").mkdir()
        (res / "values" / "strings.xml").write_text(
            '<resources><string name="watch_preset_run">Running</string>'
            '<string name="manual_preset_run" translatable="false">@string/watch_preset_run</string>'
            f'{english_extra}</resources>', encoding="utf-8")
        (res / "values-de" / "strings.xml").write_text(
            '<resources><string name="watch_preset_run">Laufen</string></resources>', encoding="utf-8")
        return res

    def test_reference_takes_the_text_of_each_language(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = self._res(tmp)
            strings = build_catalog(res)["strings"]
            tables = build_tables(res)
        entry = strings["manual_preset_run"]
        self.assertNotIn("shouldTranslate", entry)
        self.assertEqual("Running", entry["localizations"]["en"]["stringUnit"]["value"])
        self.assertEqual("Laufen", entry["localizations"]["de"]["stringUnit"]["value"])
        self.assertEqual("Laufen", tables["de"]["manual_preset_run"])
        self.assertEqual("Running", tables["fr"]["manual_preset_run"])

    def test_reference_to_a_missing_text_stops(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = self._res(tmp, '<string name="broken">@string/nowhere</string>')
            with self.assertRaises(SystemExit):
                build_tables(res)


class TableTest(unittest.TestCase):
    def test_android_format_and_english_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = Path(tmp)
            (res / "values").mkdir()
            (res / "values-de").mkdir()
            (res / "values" / "strings.xml").write_text(
                '<resources>'
                '<string name="hello">Hello %1$s, it\\\'s %2$d</string>'
                '<string name="only_en">Only English</string>'
                '<plurals name="waiting"><item quantity="one">%d change</item><item quantity="other">%d changes</item></plurals>'
                '</resources>', encoding="utf-8")
            (res / "values-de" / "strings.xml").write_text(
                '<resources><string name="hello">Hallo %1$s, es ist %2$d</string></resources>', encoding="utf-8")
            tables = build_tables(res)

        self.assertEqual("Hello %1$s, it's %2$d", tables["en"]["hello"])
        self.assertEqual("Hallo %1$s, es ist %2$d", tables["de"]["hello"])
        self.assertEqual("Only English", tables["de"]["only_en"])
        self.assertEqual({"one": "%d change", "other": "%d changes"}, tables["de"]["waiting"])
        self.assertEqual(set(tables), {"en", "de", "fr", "it", "rm", "gsw", "nb", "fi", "sv"})


class PlaceholderTest(unittest.TestCase):
    def test_translation_with_other_placeholders_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = Path(tmp)
            (res / "values").mkdir()
            (res / "values-de").mkdir()
            (res / "values" / "strings.xml").write_text(
                '<resources><string name="a">%1$s: %2$d</string><string name="b">%s</string></resources>', encoding="utf-8")
            (res / "values-de" / "strings.xml").write_text(
                '<resources><string name="a">%1$s</string><string name="b">%s</string></resources>', encoding="utf-8")
            problems = placeholder_problems(res)
        self.assertEqual(1, len(problems))
        self.assertTrue(problems[0].startswith("de/a:"))


if __name__ == "__main__":
    unittest.main()
