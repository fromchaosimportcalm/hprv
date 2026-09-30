# hprv-portal

A web page for an HPRV realm: is the server up, who's on, and what is
everyone wearing. Read-only, with no logins. Anyone who can reach the
port sees every character, which on a LAN or site-to-site network is
just the group.

- **Realm bar:** online / offline, uptime, players on, bots on.
- **One section per person:** the character they're logged in as, as a
  card (level, played, gold, average item level, guild, where they are).
  Their bots are chips underneath: the rest of their account, plus any
  summoned pool bots in their group. The logged-in character is read
  from the saved client latency (bots always save 0), so for up to one
  `PlayerSaveInterval` after a login the card shows the `[players]`
  character instead.
- **Raid pool:** summoned pool bots (type-2 `RNDBOT` accounts) that are
  online but not in anyone's group.
- **Click any character** for their equipped gear, with Wowhead
  tooltips on hover.
- **`/status.json`:** the same data for scripts.

The page refreshes itself every minute.

## Install (on the server, as root)

```bash
tar xzf hprv-portal-*.tar.gz
cd hprv-portal-*/
./install.sh
```

Then open `http://<server-ip>:8096/`. Re-run `install.sh` to update;
it keeps your config. `./uninstall.sh` removes everything it added.

It needs `python3` 3.8+ and the `mysql` client, both already on an
HPRV box. Nothing comes from pip. It makes its own MySQL user,
`hprv_portal`, which can only `SELECT` the tables the page shows, and on
`account` only the `id` and `username` columns, so it can't see
passwords.

## Say who plays what

By default each human account's most-played character is treated as the
person, and the account name as their name. To set it properly, edit
`/etc/hprv/portal.ini`:

```ini
[players]
Clinton = Bullwark
Sam = Thornhoof
```

then `systemctl restart hprv-portal`. Every other character on that
account is shown as that person's bots.

## Good to know

- **Accounts starting `RNDBOT` are bots.** If you changed
  `AiPlayerbot.RandomBotAccountPrefix`, change `bot_account_prefix` to
  match.
- **Browsers load icons and tooltips from wowhead.com and zamimg.com,**
  and fonts from Google. The server itself never calls out.
- **Average item level counts empty slots as zero** over 17 slots
  (not shirt or tabard). A two-hander counts twice.
- **Location is the map, not the zone** ("Outland", "Black Temple").
  Zone names live in the client's DBC files, which this never reads.
- **Gems aren't shown in tooltips yet,** only the permanent enchant.
  Sockets store enchant ids, and mapping them back to gem items also
  needs DBC data.
- **Port:** set `HPRV_PORTAL_PORT=8080 ./install.sh` on first install,
  or edit `port` in `portal.ini` later.
- **Logs:** `journalctl -u hprv-portal -f`

## Development

`hprv_portal.py` is one file, standard library only. Tests:

```bash
cd portal && python3 -m unittest test_portal.py
```

To try a change on HPRV itself:

```bash
rsync -a --exclude __pycache__ portal/ root@192.168.4.124:/opt/hprv/portal-src/
ssh root@192.168.4.124 /opt/hprv/portal-src/install.sh
```

To build the package for another server: `./scripts/package-portal.sh`.
