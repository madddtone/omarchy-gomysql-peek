# GoMySQL Peek

A fullscreen [Omarchy](https://omarchy.org) shell overlay for quickly peeking at
MySQL data — pick a connection, browse databases and tables, page through rows,
search every column, and run read-only SQL queries, all from the keyboard.

```
┌──────────────────────────────────────────────────────────┐
 │ users                                    / search · q …  │
│ iwos3 › iwos3 › users                                    │
├──────────────────────────────────────────────────────────┤
│ id  first_name  last_name  country_code  telephone  …    │
│ 1   admin        NULL        +62           81315…       │
├──────────────────────────────────────────────────────────┤
│ 1–50 of 1234                          ◀ Prev    Next ▶   │
└──────────────────────────────────────────────────────────┘
```

## How it works

- `engine/` — a small headless **Go** binary (`omysql-engine`,
  [go-sql-driver/mysql](https://github.com/go-sql-driver/mysql)) that speaks
  JSON on stdout. Quickshell has no MySQL client, so this engine is the entire
  data layer: connections, listing, paging, search, and a read-only guard.
- `DbPeek.qml` — an Omarchy shell **overlay plugin** (Quickshell/QML) that
  runs the engine and renders the results.

Connection profiles live in `~/.config/gomysql/connections.json` (override the
path with `GOMYSQL_CONNECTIONS`). The overlay can create, edit, and delete
profiles itself (`n` / `e` / `d`); the format is shared with the
[gomysql](https://github.com/madddtone/gomysql) desktop client. Note that
passwords are stored in plaintext with `0600` permissions on that file.

The engine's keyword guard only passes read-only statements (SELECT, SHOW,
DESCRIBE, EXPLAIN, WITH, ...), single-statement only. Passwords never leave
the engine process; the UI only ever sees name/host/user/database.

## Install

Requirements: an Omarchy system (with `omarchy-shell`), [Go](https://go.dev)
to build the engine, and a reachable MySQL server.

```bash
omarchy plugin add https://github.com/madddtone/omarchy-gomysql-peek.git --enable
~/.config/omarchy/plugins/madddtone.gomysql-peek/install.sh
```

`omarchy plugin add` clones and enables the plugin; `install.sh` builds the
engine to `~/.local/bin/omysql-engine` (the one step the plugin installer
can't do for you).

Then summon it:

```bash
omarchy-shell shell toggle madddtone.gomysql-peek
```

You can also jump straight into a table:

```bash
omarchy-shell shell summon madddtone.gomysql-peek '{"profile":"iwos3","database":"iwos3","table":"users"}'
```

### Keybind

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + I", "GoMySQL Peek", "omarchy-shell shell toggle madddtone.gomysql-peek")
```

### Menu entry

In `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"gomysql-peek": { "label": "GoMySQL Peek", "action": "omarchy-shell shell toggle madddtone.gomysql-peek", "aliases": ["gomysql", "mysql", "database"] }
```

### Uninstall

```bash
omarchy plugin remove madddtone.gomysql-peek
rm ~/.local/bin/omysql-engine
```

## Keys

| Key          | Action                                          |
|--------------|-------------------------------------------------|
| ↑ / ↓        | Move selection (PgUp/PgDn ±8, Home/End ends)    |
| ⏎            | Data view: open/close the row's field-value view. Lists: open. SQL/search box: run/apply |
| type         | Filter the current list — each screen keeps its own filter |
| `/`          | Search all columns of the open table (LIKE)     |
| `q`          | Open the read-only SQL box                      |
| ← / →        | Previous / next page (row detail: previous/next row) |
| `r`          | Refresh what you are viewing (re-runs the query or reloads rows) |
| ⇧R           | Reload the table fresh (drops query + search)   |
| Esc          | Back one level. In the data view press twice (guard against accidental exit) — first press also closes the row detail |
| click outside| Close                                           |

### Managing connections (profiles view)

| Key | Action                                                        |
|-----|---------------------------------------------------------------|
| `n` | New connection form (Enter steps through fields, saves)       |
| `e` | Edit the selected connection (password prefilled)             |
| `d` | Delete the selected connection (with confirmation)            |

Flow: connections → databases → tables → rows.

## Engine CLI

The plugin drives `~/.local/bin/omysql-engine`; you can use it directly too:

```bash
omysql-engine profiles
omysql-engine profile get --name iwos3          # full profile incl. password
omysql-engine profile save --name prod --host db.local --port 3306 --user app --password secret --database shop
omysql-engine profile remove --name prod
omysql-engine dbs --profile iwos3
omysql-engine tables --profile iwos3 --db iwos3
omysql-engine rows --profile iwos3 --db iwos3 --table users --limit 50 --offset 0 --search smith
omysql-engine query --profile iwos3 --db iwos3 --sql "SELECT id, email FROM users LIMIT 10"
```

All commands print JSON to stdout and errors to stderr. `--profile` must
match a `name` in `~/.config/gomysql/connections.json` (override the file
location with `GOMYSQL_CONNECTIONS`). `rows` caps pages at 500 rows;
`query` caps results at 500 rows (`--max-rows` up to 5000) and rejects any
statement that is not read-only.

## Development

From a plain checkout, `./install.sh` builds the engine, links the plugin
files into `~/.config/omarchy/plugins/`, enables it, and restarts the shell.
After QML edits run `omarchy restart shell` (symlinked files don't hot-reload).

```
manifest.json    plugin manifest (kind: overlay, id madddtone.gomysql-peek)
DbPeek.qml       the overlay UI
Peek.js          parsing/format helpers
engine/          the Go data engine (module gomysql-peek/engine)
install.sh       engine build + (dev) link/enable/restart
```

## License

[MIT](LICENSE)
