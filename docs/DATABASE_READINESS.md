# Database readiness and development handoff

Observed 2026-09-26. Production settings and player data were not modified.
No panel database was created, no MySQL login was attempted, and no migration ran.

## Verified from the live filesystem

- `garrysmod/data/zbattle/sql.json` selects `sqlite`; its MySQL fields are blank or placeholders.
- `garrysmod/sv.db` is 29,081,600 bytes and has 54 tables, including SQLite metadata.
- No MySQLOO/tmysql module was found in `garrysmod/lua/bin` or `garrysmod/bin`.
  This is a file-presence check, not a module-load or architecture test.
- The SSH container has the MariaDB 11.8.6 command-line client. This is NOT a
  statement about Physgun's database server version or a substitute for MySQLOO.
- The available Physgun CLI exposes server/console actions, not database creation.
  No authenticated panel/database-management action was available in this pass.
- The panel screenshot shows `chi-s-game-4.physgun.com` in the Host field.
  A selectable panel option must be chosen; typed search text alone proves nothing.
  The actual database endpoint, port, credentials and allowed source IP remain unknown.
  The SSH container and game-server container may have different network identities.

## Private SQLite snapshot completed

A bounded SQLite online backup was streamed to the user's PC and checked by SHA-256.
Both the snapshot and a separate local restore copy passed `PRAGMA quick_check`;
the restored copy retained 54 tables. No real player rows were printed in chat.
Local destination: `D:\US1-Private-Backups\20260926T053119Z\sv.db`.
The new backup directory has inheritance disabled and a current-user-only ACL.
The companion `manifest.json` records size, hash, timestamp and scope.
This is a database-only backup, NOT a full game-server or application restore test.
The roughly 3.12 GB observed under `data/` and private configuration were not copied.

## Source inventory for consolidation

`../manifests/storage-audit.json` maps the observed tables to literal references.
The 2,590 loose Lua files contain matches in 23 direct-SQLite files, 14 wrapper
files, eight PData files and 428 file-storage files. These groups can overlap.
Twenty table names have no literal match in this incomplete loose-source snapshot.
Do NOT remove those tables: dynamic names, external/archived addons and historical
systems remain unresolved. Text matches also include comments and inactive files.
The 153 inventoried GMAs are still unextracted; no archive work occurred here.

## Development checker prepared, not connected

`tools/check_dev_database.py` uses the MariaDB CLI to run fixed, read-only probes.
It accepts only `us1_dev` or a panel-prefixed `*_us1_dev` name, rejects credentials
inside Git, restricts client options, forces TLS/certificate verification, and
never puts the password on the command line. It reads connection/table-count
metadata, not player records, and has no DDL or data-writing commands.
Copy `config/examples/mysql-dev.cnf.example` outside all Git trees before filling
it locally. This file is not ZCity's live JSON configuration. Keep the live JSON
on SQLite. On the SSH host use owner-only permissions for the private option file.

Example after panel creation and private credential setup (paths are illustrative):
```sh
python3 /path/to/check_dev_database.py \
  --config "$HOME/.config/us1/mysql-dev.cnf" --database s123_us1_dev
```
Seven offline unit tests pass. No authenticated database connection, live GMod
module load, migration, outage test or production cutover has been validated.
A successful SSH-container probe does not prove game-container connectivity.
If TLS fails, obtain the correct endpoint/CA from Physgun; do not bypass verification.

## Remaining panel action and later gates

Create an EMPTY development database named `us1_dev` on the offered host.
Prefer a confirmed source-IP restriction. `%` is a broad wildcard, not an IP;
if temporarily used to bootstrap an empty dev database, keep real data out and
narrow it to the confirmed source before production use. Passwords remain private.
Record the exact database endpoint, port, prefixed name and user after creation.
Finish the full addon import/storage ownership inventory before moving any data.
Confirm the game process's architecture before installing a native driver on an
isolated test server. Verify backups of remaining operational files before deployment.

References checked 2026-09-26:
- https://docs.python.org/3/library/sqlite3.html (online backup API)
- https://github.com/FredyH/MySQLOO (native driver installation and connection API)
- https://mariadb.com/docs/server/clients-and-utilities/mariadb-client/mariadb-command-line-client
- https://dev.mysql.com/doc/refman/8.4/en/account-names.html (host restrictions)
