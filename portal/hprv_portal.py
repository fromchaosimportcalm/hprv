#!/usr/bin/env python3
"""hprv-portal: a read-only web page for an HPRV realm.

Is the server up, who is on, and what is everyone wearing. No logins,
no writes. Anyone who can reach the port sees everything, which on a
LAN / site-to-site network is the whole group. See portal/README.md.

Standard library only, on purpose: the database is read by shelling out
to the `mysql` client, the same way every script in scripts/ does, so
installing this on another HPRV box needs nothing from pip.

    hprv_portal.py [--config /etc/hprv/portal.ini]
"""

import argparse
import configparser
import html
import json
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATIC = HERE / "static"
ICONS = "https://wow.zamimg.com/images/wow/icons"
WOWHEAD_ITEM = "https://www.wowhead.com/wotlk/item="

CLASSES = {  # id -> (name, icon slug, class colour)
    1: ("Warrior", "warrior", "#C79C6E"),
    2: ("Paladin", "paladin", "#F58CBA"),
    3: ("Hunter", "hunter", "#ABD473"),
    4: ("Rogue", "rogue", "#FFF569"),
    5: ("Priest", "priest", "#FFFFFF"),
    6: ("Death Knight", "deathknight", "#C41F3B"),
    7: ("Shaman", "shaman", "#0070DE"),
    8: ("Mage", "mage", "#69CCF0"),
    9: ("Warlock", "warlock", "#9482C9"),
    11: ("Druid", "druid", "#FF7D0A"),
}
RACES = {  # id -> (name, icon slug). Wowhead calls Undead "scourge".
    1: ("Human", "human"), 2: ("Orc", "orc"), 3: ("Dwarf", "dwarf"),
    4: ("Night Elf", "nightelf"), 5: ("Undead", "scourge"),
    6: ("Tauren", "tauren"), 7: ("Gnome", "gnome"), 8: ("Troll", "troll"),
    10: ("Blood Elf", "bloodelf"), 11: ("Draenei", "draenei"),
}
QUALITY = ["poor", "common", "uncommon", "rare", "epic", "legendary",
           "artifact", "heirloom"]
SLOTS = ["Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs",
         "Feet", "Wrist", "Hands", "Finger", "Finger", "Trinket", "Trinket",
         "Back", "Main Hand", "Off Hand", "Ranged", "Tabard"]
# The 17 slots that count toward average item level (not shirt, tabard).
ILVL_SLOTS = [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
INVTYPE_2H = 17
# characters.zone is an area id whose names live in DBC, which this
# never reads. The map id is enough to say "in Black Temple".
MAPS = {
    0: "Eastern Kingdoms", 1: "Kalimdor", 530: "Outland", 571: "Northrend",
    532: "Karazhan", 565: "Gruul's Lair", 544: "Magtheridon's Lair",
    548: "Serpentshrine Cavern", 550: "Tempest Keep", 534: "Mount Hyjal",
    564: "Black Temple", 568: "Zul'Aman", 580: "Sunwell Plateau",
    609: "Ebon Hold",
}


# ---------------------------------------------------------------- formatting

def fmt_played(seconds):
    seconds = int(seconds)
    d, rem = divmod(seconds, 86400)
    h, rem = divmod(rem, 3600)
    if d:
        return f"{d}d {h}h"
    return f"{h}h {rem // 60}m"


def fmt_gold(copper):
    return f"{int(copper) // 10000:,} g"


def avg_ilvl(items):
    """items: {slot: (item_level, inventory_type)} for equipped gear.

    Empty slots count as zero, so a half-naked character reads low, the
    way the gear-score addons read it. A two-hander with an empty off
    hand counts twice, since there is no off hand to be had.
    """
    if not items:
        return 0
    total = sum(items[s][0] for s in ILVL_SLOTS if s in items)
    mh = items.get(15)
    if mh and mh[1] == INVTYPE_2H and 16 not in items:
        total += mh[0]
    return round(total / len(ILVL_SLOTS))


def perm_enchant(enchantments):
    """item_instance.enchantments is 'id duration charges' per slot;
    slot 0 is the permanent enchant. Returns its id, or 0."""
    parts = (enchantments or "").split()
    return int(parts[0]) if parts and parts[0].isdigit() else 0


def e(s):
    return html.escape(str(s), quote=True)


# ---------------------------------------------------------------- database

class Db:
    def __init__(self, cfg):
        d = cfg["database"]
        self.cnf = d.get("client_config", "/etc/hprv/portal.cnf")
        self.auth = d.get("auth", "acore_auth")
        self.chars = d.get("characters", "acore_characters")
        self.world = d.get("world", "acore_world")
        self.bots = d.get("playerbots", "acore_playerbots")

    def query(self, sql):
        # --defaults-extra-file must be the first option. --raw so values
        # are not backslash-escaped; nothing selected here holds a tab.
        out = subprocess.run(
            ["mysql", f"--defaults-extra-file={self.cnf}",
             "--default-character-set=utf8mb4", "-N", "-B", "--raw",
             "-e", sql],
            capture_output=True, text=True, timeout=10)
        if out.returncode != 0:
            raise RuntimeError(out.stderr.strip() or "mysql failed")
        return [line.split("\t") for line in out.stdout.splitlines()]

    def char_select(self, where):
        return f"""
        SELECT c.guid, c.account, a.username, COALESCE(t.account_type, -1),
               c.name, c.race, c.class, c.gender, c.level, c.money,
               c.totaltime, c.online, c.map, COALESCE(g.name, ''),
               c.latency
          FROM {self.chars}.characters c
          JOIN {self.auth}.account a ON a.id = c.account
          LEFT JOIN {self.bots}.playerbots_account_type t
                 ON t.account_id = c.account
          LEFT JOIN {self.chars}.guild_member gm ON gm.guid = c.guid
          LEFT JOIN {self.chars}.guild g ON g.guildid = gm.guildid
         WHERE c.deleteDate IS NULL AND ({where})"""

    def characters(self, bot_prefix):
        # Every character on a human account, plus whatever bots are
        # online. Offline RNDBOT characters number in the hundreds and
        # nobody wants them on a page.
        rows = self.query(self.char_select(
            f"a.username NOT LIKE '{bot_prefix}%' OR c.online = 1"))
        return [Character(r) for r in rows]

    def group_of(self):
        """{character guid: group id} for everyone in a party or raid."""
        rows = self.query(f"SELECT memberGuid, guid FROM {self.chars}.group_member")
        return {int(m): int(g) for m, g in rows}

    def character(self, guid):
        rows = self.query(self.char_select(f"c.guid = {int(guid)}"))
        return Character(rows[0]) if rows else None

    def ilvl_items(self, guids):
        if not guids:
            return {}
        rows = self.query(f"""
        SELECT ci.guid, ci.slot, it.ItemLevel, it.InventoryType
          FROM {self.chars}.character_inventory ci
          JOIN {self.chars}.item_instance ii ON ii.guid = ci.item
          JOIN {self.world}.item_template it ON it.entry = ii.itemEntry
         WHERE ci.bag = 0 AND ci.slot < 19
           AND ci.guid IN ({",".join(str(int(g)) for g in guids)})""")
        items = {}
        for guid, slot, ilvl, invtype in rows:
            items.setdefault(int(guid), {})[int(slot)] = (int(ilvl), int(invtype))
        return items

    def gear(self, guid):
        rows = self.query(f"""
        SELECT ci.slot, ii.itemEntry, it.name, it.Quality, it.ItemLevel,
               it.InventoryType, COALESCE(ii.enchantments, '')
          FROM {self.chars}.character_inventory ci
          JOIN {self.chars}.item_instance ii ON ii.guid = ci.item
          JOIN {self.world}.item_template it ON it.entry = ii.itemEntry
         WHERE ci.bag = 0 AND ci.slot < 19 AND ci.guid = {int(guid)}
         ORDER BY ci.slot""")
        return [{"slot": int(r[0]), "entry": int(r[1]), "name": r[2],
                 "quality": int(r[3]), "ilvl": int(r[4]),
                 "invtype": int(r[5]), "ench": perm_enchant(r[6])}
                for r in rows]

    def realm(self, realm_id):
        rows = self.query(f"""
        SELECT r.name,
               COALESCE((SELECT u.starttime FROM {self.auth}.uptime u
                          WHERE u.realmid = r.id
                          ORDER BY u.starttime DESC LIMIT 1), 0)
          FROM {self.auth}.realmlist r WHERE r.id = {int(realm_id)}""")
        return (rows[0][0], int(rows[0][1])) if rows else ("?", 0)


class Character:
    def __init__(self, r):
        self.guid, self.account = int(r[0]), int(r[1])
        self.username, self.account_type = r[2], int(r[3])
        self.name = r[4]
        self.race, self.cls, self.gender = int(r[5]), int(r[6]), int(r[7])
        self.level, self.money, self.played = int(r[8]), int(r[9]), int(r[10])
        self.online, self.map, self.guild = r[11] == "1", int(r[12]), r[13]
        # The client's last reported latency, written on every save. A
        # bot has no client, so it always saves 0.
        self.latency = int(r[14] or 0)
        self.ilvl = 0

    @property
    def class_name(self):
        return CLASSES.get(self.cls, (f"Class {self.cls}",))[0]

    @property
    def colour(self):
        return CLASSES.get(self.cls, (None, None, "#999999"))[2]

    @property
    def race_name(self):
        return RACES.get(self.race, (f"Race {self.race}",))[0]

    @property
    def portrait(self):
        slug = RACES.get(self.race, (None, None))[1]
        if not slug:
            return f"{ICONS}/large/inv_misc_questionmark.jpg"
        sex = "female" if self.gender == 1 else "male"
        return f"{ICONS}/large/race_{slug}_{sex}.jpg"

    @property
    def class_icon(self):
        slug = CLASSES.get(self.cls, (None, None))[1]
        return f"{ICONS}/medium/classicon_{slug or 'warrior'}.jpg"

    @property
    def where(self):
        return MAPS.get(self.map, "In the world")

    def as_json(self):
        return {"name": self.name, "class": self.class_name,
                "race": self.race_name, "level": self.level,
                "item_level": self.ilvl, "online": self.online,
                "where": self.where if self.online else None}


# ---------------------------------------------------------------- snapshot

def port_open(host, port):
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


class Snapshot:
    """Everything the front page needs, read once and cached briefly so
    a room full of refreshing browsers doesn't become a query storm."""

    def __init__(self, cfg, db):
        p = cfg["portal"]
        self.db = db
        self.prefix = p.get("bot_account_prefix", "RNDBOT").upper()
        self.realm_id = p.getint("realm_id", 1)
        self.host = p.get("server_host", "127.0.0.1")
        self.auth_port = p.getint("auth_port", 3724)
        self.world_port = p.getint("world_port", 8085)
        self.ttl = p.getint("cache_seconds", 15)
        # [players] Name = MainCharacter. Keys keep their case.
        self.mains = {v.strip().lower(): k for k, v in cfg["players"].items()}
        self._lock = threading.Lock()
        self._at, self._data = 0.0, None

    def get(self):
        with self._lock:
            if self._data is None or time.time() - self._at > self.ttl:
                self._data = self._build()
                self._at = time.time()
            return self._data

    def _build(self):
        world_up = port_open(self.host, self.world_port)
        auth_up = port_open(self.host, self.auth_port)
        realm_name, started = self.db.realm(self.realm_id)
        chars = self.db.characters(self.prefix)

        humans = [c for c in chars if not c.username.upper().startswith(self.prefix)]
        bots = [c for c in chars if c.username.upper().startswith(self.prefix)]
        pool = [c for c in bots if c.account_type == 2]       # summoned raid pool
        ambient = [c for c in bots if c.account_type != 2]    # the world's randoms

        ilvls = self.db.ilvl_items([c.guid for c in humans + pool])
        for c in humans + pool:
            c.ilvl = avg_ilvl(ilvls.get(c.guid, {}))

        players = {}
        for c in humans:
            players.setdefault(c.account, []).append(c)
        groups = [self._player(cs) for cs in players.values()]

        # A summoned pool bot is listed under whoever it is grouped with.
        # The rest stay in the raid pool section.
        group_of = self.db.group_of() if pool else {}
        for g in groups:
            gid = group_of.get(g["main"].guid)
            if gid is None or not g["online"]:
                continue
            mine = [c for c in pool if group_of.get(c.guid) == gid]
            g["bots"] += sorted(mine, key=lambda c: (-c.level, c.name))
            pool = [c for c in pool if c not in mine]
        # Online first, then by name.
        groups.sort(key=lambda g: (not g["online"], g["player"].lower()))

        pool.sort(key=lambda c: (-c.ilvl, c.name))
        return {
            "realm": realm_name,
            "world_up": world_up, "auth_up": auth_up,
            "uptime": int(time.time()) - started if world_up and started else 0,
            "players": groups,
            "pool": pool,
            "ambient_online": len(ambient),
            "built": time.strftime("%H:%M:%S"),
        }

    def _player(self, chars):
        """One human account: who they are, which character they are
        on, and the rest of the account as their bots."""
        configured = next((c for c in chars if c.name.lower() in self.mains), None)
        player = (self.mains[configured.name.lower()] if configured
                  else chars[0].username.title())
        online = [c for c in chars if c.online]
        # The character the person is logged in as is the one with a
        # client. Latency only reaches the DB on a save (PlayerSaveInterval,
        # 15 min here), so for the first minutes after a login fall back
        # to the configured character, then the most-played online one.
        with_client = [c for c in online if c.latency > 0]
        if with_client:
            main = max(with_client, key=lambda c: c.latency)
        elif configured and (configured.online or not online):
            main = configured
        else:
            main = max(online or chars, key=lambda c: c.played)
        rest = sorted((c for c in chars if c is not main),
                      key=lambda c: (not c.online, -c.level, c.name))
        # Bots on your own account only log in with you, so any character
        # online on the account means the person is at the keyboard.
        return {"player": player, "main": main, "bots": rest,
                "online": any(c.online for c in chars)}


# ---------------------------------------------------------------- rendering

def page(title, body, refresh=None):
    meta = f'<meta http-equiv="refresh" content="{refresh}">' if refresh else ""
    return f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{meta}
<title>{e(title)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&family=Inter:wght@400;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/static/style.css">
<script>const whTooltips = {{colorLinks: true, iconizeLinks: true, renameLinks: false, iconSize: 'medium'}};</script>
<script src="https://wow.zamimg.com/js/tooltips.js"></script>
</head><body><main>
{body}
</main></body></html>"""


def realm_bar(s):
    up = s["world_up"] and s["auth_up"]
    if up:
        state = '<span class="dot on"></span>Online'
    elif s["auth_up"]:
        state = '<span class="dot warn"></span>Login up, world down'
    else:
        state = '<span class="dot off"></span>Offline'
    humans = sum(1 for g in s["players"] if g["online"])
    bots = s["ambient_online"] + len(s["pool"]) + sum(
        1 for g in s["players"] for c in g["bots"] if c.online)
    uptime = fmt_played(s["uptime"]) if s["uptime"] else "–"
    return f"""
<header class="realm">
  <h1>{e(s["realm"])}</h1>
  <div class="realm-stats">
    <div><span>Realm</span><b>{state}</b></div>
    <div><span>Uptime</span><b>{uptime}</b></div>
    <div><span>Players on</span><b>{humans}</b></div>
    <div><span>Bots on</span><b>{bots}</b></div>
  </div>
</header>"""


def card(c):
    status = (f'<span class="st on">● {e(c.where)}</span>' if c.online
              else '<span class="st">● Offline</span>')
    guild = f"&lt;{e(c.guild)}&gt;" if c.guild else ""
    return f"""
<a class="card" style="--cc:{c.colour}" href="/c/{c.guid}">
  <div class="head">
    <div class="portrait"><img src="{c.portrait}" alt=""><img class="badge" src="{c.class_icon}" alt=""></div>
    <div class="who"><div class="name">{e(c.name)}</div><div class="sub">{e(c.class_name)} · {e(c.race_name)}</div></div>
    <div class="lvl"><span>Level</span><b>{c.level}</b></div>
  </div>
  <div class="stats">
    <div><span>Played</span><b>{fmt_played(c.played)}</b></div>
    <div><span>Gold</span><b class="gold">{fmt_gold(c.money)}</b></div>
    <div><span>Item level</span><b class="ilvl">{c.ilvl}</b></div>
  </div>
  <div class="foot"><span>{guild}</span>{status}</div>
</a>"""


def mini(c):
    return f"""
<a class="mini{' online' if c.online else ''}" style="--cc:{c.colour}" href="/c/{c.guid}" title="{e(c.class_name)} · {e(c.race_name)}">
  <img src="{c.class_icon}" alt="">
  <span class="name">{e(c.name)}</span>
  <span class="meta">{c.level} · <b>{c.ilvl}</b></span>
</a>"""


def render_index(s):
    parts = [realm_bar(s)]
    if not s["players"]:
        parts.append('<p class="empty">No player accounts yet.</p>')
    for g in s["players"]:
        dot = '<span class="dot on"></span>' if g["online"] else '<span class="dot off"></span>'
        bots = ""
        if g["bots"]:
            on = sum(1 for c in g["bots"] if c.online)
            bots = (f'<h3>Bots <small>{on} of {len(g["bots"])} online '
                    f'· level · item level</small></h3>'
                    f'<div class="minis">{"".join(mini(c) for c in g["bots"])}</div>')
        parts.append(f"""
<section class="player">
  <h2>{dot}{e(g["player"])}</h2>
  <div class="cards">{card(g["main"])}</div>
  {bots}
</section>""")
    if s["pool"]:
        parts.append(f"""
<section class="player">
  <h2>Raid pool <small>{len(s["pool"])} summoned</small></h2>
  <div class="minis">{"".join(mini(c) for c in s["pool"])}</div>
</section>""")
    parts.append(f'<footer>{s["ambient_online"]} ambient bots out in the world · '
                 f'updated {s["built"]} · <a href="/status.json">status.json</a></footer>')
    return page(s["realm"], "\n".join(parts), refresh=60)


def render_character(c, gear, realm):
    items = {g["slot"]: (g["ilvl"], g["invtype"]) for g in gear}
    c.ilvl = avg_ilvl(items)
    by_slot = {g["slot"]: g for g in gear}
    rows = []
    for slot in ILVL_SLOTS:
        g = by_slot.get(slot)
        if not g:
            rows.append(f'<tr class="missing"><th>{SLOTS[slot]}</th><td>–</td><td></td><td></td></tr>')
            continue
        q = QUALITY[g["quality"]] if g["quality"] < len(QUALITY) else "common"
        wh = f' data-wowhead="ench={g["ench"]}"' if g["ench"] else ""
        ench = '<span class="ench" title="Enchanted">✦</span>' if g["ench"] else ""
        rows.append(
            f'<tr><th>{SLOTS[slot]}</th>'
            f'<td><a class="q-{q}" href="{WOWHEAD_ITEM}{g["entry"]}"{wh}>{e(g["name"])}</a></td>'
            f'<td class="ilvl">{g["ilvl"]}</td><td>{ench}</td></tr>')
    body = f"""
<p class="back"><a href="/">← {e(realm)}</a></p>
<div class="cards">{card(c)}</div>
<section class="gear">
  <h2>Equipped <small>average item level {c.ilvl}, empty slots count as 0</small></h2>
  <table>{"".join(rows)}</table>
</section>"""
    return page(f"{c.name} · {realm}", body)


def status_json(s):
    return {
        "realm": s["realm"],
        "online": s["world_up"] and s["auth_up"],
        "world_up": s["world_up"], "auth_up": s["auth_up"],
        "uptime_seconds": s["uptime"],
        "players": [{"player": g["player"], "online": g["online"],
                     "main": g["main"].as_json(),
                     "bots_online": sum(1 for c in g["bots"] if c.online)}
                    for g in s["players"]],
        "pool_online": len(s["pool"]),
        "ambient_online": s["ambient_online"],
    }


# ---------------------------------------------------------------- http

class Handler(BaseHTTPRequestHandler):
    snapshot = None  # set in main()
    server_version = "hprv-portal"

    def send(self, code, body, ctype="text/html; charset=utf-8", cache=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        if cache:
            self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        try:
            if path == "/":
                self.send(200, render_index(self.snapshot.get()))
            elif path == "/status.json":
                self.send(200, json.dumps(status_json(self.snapshot.get()), indent=2),
                          "application/json")
            elif path.startswith("/c/") and path[3:].isdigit():
                db = self.snapshot.db
                c = db.character(int(path[3:]))
                if c is None:
                    self.send(404, page("Not found", '<p class="empty">No such character. <a href="/">Back</a></p>'))
                else:
                    self.send(200, render_character(c, db.gear(c.guid),
                                                    self.snapshot.get()["realm"]))
            elif path == "/static/style.css":
                self.send(200, (STATIC / "style.css").read_bytes(),
                          "text/css; charset=utf-8", cache="max-age=300")
            else:
                self.send(404, page("Not found", '<p class="empty">Nothing here. <a href="/">Back</a></p>'))
        except Exception as ex:  # a down DB should be a page, not a hang
            self.log_error("error on %s: %s", path, ex)
            self.send(503, page("Unavailable",
                                '<p class="empty">Can\'t read the realm database right now.</p>',
                                refresh=30))

    def log_message(self, fmt, *args):
        # journald adds its own timestamp
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def load_config(path):
    cfg = configparser.ConfigParser()
    cfg.optionxform = str  # keep player names' case
    cfg.read_dict({"portal": {}, "database": {}, "players": {}})
    if not cfg.read(path):
        sys.exit(f"cannot read config {path}")
    return cfg


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", default="/etc/hprv/portal.ini")
    args = ap.parse_args()
    cfg = load_config(args.config)
    Handler.snapshot = Snapshot(cfg, Db(cfg))
    bind = cfg["portal"].get("bind", "0.0.0.0")
    port = cfg["portal"].getint("port", 8096)
    srv = ThreadingHTTPServer((bind, port), Handler)
    print(f"hprv-portal listening on http://{bind}:{port}", file=sys.stderr, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
