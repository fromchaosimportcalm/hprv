"""Tests for the parts of hprv_portal that need no database.

    python3 -m unittest portal/test_portal.py      # from the repo root
"""

import configparser
import unittest

import hprv_portal as p


def char(**kw):
    row = {"guid": 1, "account": 101, "username": "CLINTON", "type": -1,
           "name": "Bullwark", "race": 6, "cls": 1, "gender": 0, "level": 70,
           "money": 250000, "played": 137000, "online": 0, "map": 530,
           "guild": "", "latency": 0}
    row.update(kw)
    return p.Character([str(row[k]) for k in
                        ("guid", "account", "username", "type", "name", "race",
                         "cls", "gender", "level", "money", "played", "online",
                         "map", "guild", "latency")])


class Formatting(unittest.TestCase):
    def test_played(self):
        self.assertEqual(p.fmt_played(137000), "1d 14h")
        self.assertEqual(p.fmt_played(3720), "1h 2m")

    def test_gold(self):
        self.assertEqual(p.fmt_gold(12345678), "1,234 g")

    def test_perm_enchant(self):
        self.assertEqual(p.perm_enchant("3818 0 0 0 0 0 3525 0 0 "), 3818)
        self.assertEqual(p.perm_enchant("0 0 0 "), 0)
        self.assertEqual(p.perm_enchant(""), 0)

    def test_escape(self):
        self.assertEqual(p.e('<b>"x"'), "&lt;b&gt;&quot;x&quot;")


class ItemLevel(unittest.TestCase):
    def test_full_set(self):
        items = {s: (100, 1) for s in p.ILVL_SLOTS}
        self.assertEqual(p.avg_ilvl(items), 100)

    def test_shirt_and_tabard_ignored(self):
        items = {s: (100, 1) for s in p.ILVL_SLOTS}
        items[3] = items[18] = (1, 4)
        self.assertEqual(p.avg_ilvl(items), 100)

    def test_two_hander_counts_twice(self):
        items = {s: (100, 1) for s in p.ILVL_SLOTS if s != 16}
        items[15] = (100, p.INVTYPE_2H)
        self.assertEqual(p.avg_ilvl(items), 100)

    def test_empty_slot_counts_zero(self):
        items = {s: (100, 1) for s in p.ILVL_SLOTS if s != 0}
        self.assertEqual(p.avg_ilvl(items), round(1600 / 17))

    def test_naked(self):
        self.assertEqual(p.avg_ilvl({}), 0)


class Characters(unittest.TestCase):
    def test_icons(self):
        c = char(race=5, gender=1, cls=6)
        self.assertTrue(c.portrait.endswith("race_scourge_female.jpg"))
        self.assertTrue(c.class_icon.endswith("classicon_deathknight.jpg"))
        self.assertEqual(c.class_name, "Death Knight")

    def test_unknown_race_does_not_crash(self):
        c = char(race=99, cls=99)
        self.assertIn("questionmark", c.portrait)
        self.assertEqual(c.colour, "#999999")

    def test_where(self):
        self.assertEqual(char(map=564).where, "Black Temple")
        self.assertEqual(char(map=9999).where, "In the world")


class Players(unittest.TestCase):
    def snapshot(self, players=""):
        cfg = configparser.ConfigParser()
        cfg.optionxform = str
        cfg.read_string("[portal]\n[database]\n[players]\n" + players)
        return p.Snapshot(cfg, db=None)

    def test_configured_main(self):
        s = self.snapshot("Clinton = Bullwark\n")
        cs = [char(name="Crumm", played=999999), char(guid=2, name="Bullwark")]
        g = s._player(cs)
        self.assertEqual(g["player"], "Clinton")
        self.assertEqual(g["main"].name, "Bullwark")
        self.assertEqual([c.name for c in g["bots"]], ["Crumm"])

    def test_unconfigured_uses_most_played(self):
        s = self.snapshot()
        g = s._player([char(name="Alt", played=10), char(guid=2, name="Main", played=500)])
        self.assertEqual(g["player"], "Clinton")
        self.assertEqual(g["main"].name, "Main")

    def test_logged_in_character_is_the_card(self):
        s = self.snapshot("Clinton = Bullwark\n")
        g = s._player([char(name="Bullwark", online=1),
                       char(guid=2, name="Nathos", online=1, latency=42)])
        self.assertEqual(g["player"], "Clinton")
        self.assertEqual(g["main"].name, "Nathos")
        self.assertEqual([c.name for c in g["bots"]], ["Bullwark"])

    def test_before_first_save_uses_configured(self):
        s = self.snapshot("Clinton = Bullwark\n")
        g = s._player([char(name="Crumm", online=1, played=999999),
                       char(guid=2, name="Bullwark", online=1)])
        self.assertEqual(g["main"].name, "Bullwark")

    def test_offline_configured_not_shown_as_playing(self):
        s = self.snapshot("Clinton = Bullwark\n")
        g = s._player([char(name="Nathos", online=1, played=5),
                       char(guid=2, name="Bullwark", online=0, played=999)])
        self.assertEqual(g["main"].name, "Nathos")

    def test_online_if_any_character_online(self):
        s = self.snapshot()
        g = s._player([char(online=0), char(guid=2, name="Bot", online=1)])
        self.assertTrue(g["online"])


class Rendering(unittest.TestCase):
    def test_hostile_names_are_escaped(self):
        c = char(name="<script>", guild="</a>")
        c.ilvl = 100
        out = p.card(c)
        self.assertNotIn("<script>", out)
        self.assertIn("&lt;script&gt;", out)


if __name__ == "__main__":
    unittest.main()
