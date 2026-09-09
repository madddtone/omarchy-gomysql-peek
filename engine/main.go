package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	_ "github.com/go-sql-driver/mysql"
)

type connProfile struct {
	Name     string `json:"name"`
	Host     string `json:"host"`
	Port     string `json:"port"`
	User     string `json:"user"`
	Password string `json:"password"`
	Database string `json:"database"`
}

type profileOut struct {
	Name     string `json:"name"`
	Host     string `json:"host"`
	Port     string `json:"port"`
	User     string `json:"user"`
	Database string `json:"database"`
}

const maxCellRunes = 4096

var readKeywords = map[string]bool{
	"SELECT": true, "SHOW": true, "DESCRIBE": true, "DESC": true,
	"EXPLAIN": true, "WITH": true, "ANALYZE": true, "VALUES": true,
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func connectionsPath() string {
	if p := os.Getenv("GOMYSQL_CONNECTIONS"); p != "" {
		return p
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		fail("cannot resolve config dir: %v", err)
	}
	return filepath.Join(dir, "gomysql", "connections.json")
}

func loadProfiles() []connProfile {
	data, err := os.ReadFile(connectionsPath())
	if err != nil {
		fail("no gomysql connections file (%s): %v", connectionsPath(), err)
	}
	var out []connProfile
	if err := json.Unmarshal(data, &out); err != nil {
		fail("cannot parse connections file: %v", err)
	}
	return out
}

func findProfile(name string) connProfile {
	for _, p := range loadProfiles() {
		if p.Name == name {
			return p
		}
	}
	fail("no connection profile named %q", name)
	return connProfile{}
}

func buildDSN(p connProfile, db string) string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?timeout=5s&readTimeout=30s&writeTimeout=30s&parseTime=true",
		url.QueryEscape(p.User), url.QueryEscape(p.Password), p.Host, p.Port, db)
}

func open(p connProfile, db string) *sql.DB {
	handle, err := sql.Open("mysql", buildDSN(p, db))
	if err != nil {
		fail("%v", err)
	}
	handle.SetMaxOpenConns(4)
	if err := handle.Ping(); err != nil {
		handle.Close()
		fail("%v", err)
	}
	return handle
}

func quoteIdent(s string) string {
	return "`" + strings.ReplaceAll(s, "`", "``") + "`"
}

func cell(v sql.NullString) any {
	if !v.Valid {
		return nil
	}
	s := v.String
	if len(s) > maxCellRunes {
		s = string([]rune(s)[:maxCellRunes]) + "…"
	}
	return s
}

func emit(v any) {
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(v); err != nil {
		fail("%v", err)
	}
}

func saveProfilesFile(list []connProfile) error {
	path := connectionsPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func cmdProfileGet(fs *flag.FlagSet) {
	name := fs.String("name", "", "connection profile name")
	_ = fs.Parse(os.Args[3:])
	if *name == "" {
		fs.Usage()
		os.Exit(2)
	}
	p := findProfile(*name)
	emit(map[string]any{"profile": p})
}

func cmdProfileSave(fs *flag.FlagSet) {
	name := fs.String("name", "", "profile name")
	host := fs.String("host", "", "host")
	port := fs.String("port", "3306", "port")
	user := fs.String("user", "", "user")
	password := fs.String("password", "", "password")
	database := fs.String("database", "", "default database")
	_ = fs.Parse(os.Args[3:])
	if *name == "" || *host == "" {
		fail("name and host are required")
	}
	if *port == "" {
		*port = "3306"
	}
	list := loadProfiles()
	p := connProfile{Name: *name, Host: *host, Port: *port, User: *user, Password: *password, Database: *database}
	replaced := false
	for i := range list {
		if list[i].Name == *name {
			list[i] = p
			replaced = true
			break
		}
	}
	if !replaced {
		list = append(list, p)
	}
	if err := saveProfilesFile(list); err != nil {
		fail("%v", err)
	}
	emit(map[string]any{"saved": *name})
}

func cmdProfileRemove(fs *flag.FlagSet) {
	name := fs.String("name", "", "profile name")
	_ = fs.Parse(os.Args[3:])
	if *name == "" {
		fs.Usage()
		os.Exit(2)
	}
	list := loadProfiles()
	out := make([]connProfile, 0, len(list))
	found := false
	for _, p := range list {
		if p.Name == *name {
			found = true
			continue
		}
		out = append(out, p)
	}
	if !found {
		fail("no connection profile named %q", name)
	}
	if err := saveProfilesFile(out); err != nil {
		fail("%v", err)
	}
	emit(map[string]any{"removed": *name})
}

func cmdProfiles() {
	profiles := loadProfiles()
	out := make([]profileOut, 0, len(profiles))
	for _, p := range profiles {
		out = append(out, profileOut{
			Name: p.Name, Host: p.Host, Port: p.Port,
			User: p.User, Database: p.Database,
		})
	}
	emit(map[string]any{"profiles": out})
}

func cmdDbs(fs *flag.FlagSet) {
	name := fs.String("profile", "", "connection profile name")
	_ = fs.Parse(os.Args[2:])
	if *name == "" {
		fs.Usage()
		os.Exit(2)
	}
	p := findProfile(*name)
	handle := open(p, "")
	defer handle.Close()
	rows, err := handle.Query("SHOW DATABASES")
	if err != nil {
		fail("%v", err)
	}
	defer rows.Close()
	dbs := []string{}
	for rows.Next() {
		var s sql.NullString
		if err := rows.Scan(&s); err != nil {
			fail("%v", err)
		}
		if s.Valid && s.String != "" {
			dbs = append(dbs, s.String)
		}
	}
	if err := rows.Err(); err != nil {
		fail("%v", err)
	}
	emit(map[string]any{"databases": dbs})
}

func cmdTables(fs *flag.FlagSet) {
	name := fs.String("profile", "", "connection profile name")
	db := fs.String("db", "", "database")
	_ = fs.Parse(os.Args[2:])
	if *name == "" {
		fs.Usage()
		os.Exit(2)
	}
	p := findProfile(*name)
	database := *db
	if database == "" {
		database = p.Database
	}
	if database == "" {
		fail("no database selected: pass --db or save a database in the profile")
	}
	handle := open(p, database)
	defer handle.Close()
	rows, err := handle.Query("SHOW TABLES")
	if err != nil {
		fail("%v", err)
	}
	defer rows.Close()
	tables := []string{}
	for rows.Next() {
		var s sql.NullString
		if err := rows.Scan(&s); err != nil {
			fail("%v", err)
		}
		if s.Valid {
			tables = append(tables, s.String)
		}
	}
	if err := rows.Err(); err != nil {
		fail("%v", err)
	}
	emit(map[string]any{"tables": tables})
}

func tableRef(database, table string) string {
	return quoteIdent(database) + "." + quoteIdent(table)
}

func readColumns(handle *sql.DB, ref string) ([]string, error) {
	rows, err := handle.Query("SHOW COLUMNS FROM " + ref)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := []string{}
	for rows.Next() {
		var field, colType, null, key, extra sql.NullString
		var def sql.NullString
		if err := rows.Scan(&field, &colType, &null, &key, &def, &extra); err != nil {
			return nil, err
		}
		cols = append(cols, field.String)
	}
	return cols, rows.Err()
}

func fetchPage(handle *sql.DB, q string, args []any, maxRows int64) ([]string, []json.RawMessage, bool, error) {
	rows, err := handle.Query(q, args...)
	if err != nil {
		return nil, nil, false, err
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		return nil, nil, false, err
	}
	vals := make([]sql.NullString, len(cols))
	ptrs := make([]any, len(cols))
	for i := range vals {
		ptrs[i] = &vals[i]
	}
	out := []json.RawMessage{}
	truncated := false
	for rows.Next() {
		if int64(len(out)) >= maxRows {
			truncated = true
			break
		}
		if err := rows.Scan(ptrs...); err != nil {
			return nil, nil, false, err
		}
		row := make([]any, len(cols))
		for i, v := range vals {
			row[i] = cell(v)
		}
		raw, err := json.Marshal(row)
		if err != nil {
			return nil, nil, false, err
		}
		out = append(out, raw)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, false, err
	}
	return cols, out, truncated, nil
}

func emitRows(cols []string, raw []json.RawMessage, total int64, offset, limit int64, truncated bool) {
	emit(map[string]any{
		"columns":   cols,
		"rows":      raw,
		"total":     total,
		"offset":    offset,
		"limit":     limit,
		"truncated": truncated,
	})
}

func cmdRows(fs *flag.FlagSet) {
	name := fs.String("profile", "", "connection profile name")
	db := fs.String("db", "", "database")
	table := fs.String("table", "", "table name")
	limitF := fs.String("limit", "50", "rows per page")
	offsetF := fs.String("offset", "0", "row offset")
	search := fs.String("search", "", "LIKE search across all columns")
	_ = fs.Parse(os.Args[2:])
	if *name == "" || *table == "" {
		fs.Usage()
		os.Exit(2)
	}
	limit, err := strconv.ParseInt(*limitF, 10, 64)
	if err != nil || limit < 1 {
		limit = 50
	}
	if limit > 500 {
		limit = 500
	}
	offset, err := strconv.ParseInt(*offsetF, 10, 64)
	if err != nil || offset < 0 {
		offset = 0
	}
	p := findProfile(*name)
	database := *db
	if database == "" {
		database = p.Database
	}
	if database == "" {
		fail("no database selected: pass --db or save a database in the profile")
	}
	handle := open(p, database)
	defer handle.Close()
	ref := tableRef(database, *table)
	cols, err := readColumns(handle, ref)
	if err != nil {
		fail("%v", err)
	}
	if len(cols) == 0 {
		fail("table %s has no columns", ref)
	}

	var total int64
	var where string
	var args []any
	if *search != "" {
		conds := make([]string, len(cols))
		args = make([]any, len(cols))
		for i, c := range cols {
			conds[i] = quoteIdent(c) + " LIKE ?"
			args[i] = "%" + *search + "%"
		}
		where = " WHERE " + strings.Join(conds, " OR ")
	}
	if err := handle.QueryRow("SELECT COUNT(*) FROM "+ref+where, args...).Scan(&total); err != nil {
		fail("%v", err)
	}

	q := "SELECT * FROM " + ref + where + " LIMIT ? OFFSET ?"
	pageArgs := append(append([]any{}, args...), limit, offset)
	pageCols, raw, truncated, err := fetchPage(handle, q, pageArgs, limit)
	if err != nil {
		fail("%v", err)
	}
	if len(pageCols) == 0 {
		pageCols = cols
	}
	emitRows(pageCols, raw, total, offset, limit, truncated)
}

func cmdQuery(fs *flag.FlagSet) {
	name := fs.String("profile", "", "connection profile name")
	db := fs.String("db", "", "database")
	sqlText := fs.String("sql", "", "read-only SQL statement")
	maxRowsF := fs.String("max-rows", "500", "maximum rows to fetch")
	_ = fs.Parse(os.Args[2:])
	if *name == "" || *sqlText == "" {
		fs.Usage()
		os.Exit(2)
	}
	maxRows, err := strconv.ParseInt(*maxRowsF, 10, 64)
	if err != nil || maxRows < 1 {
		maxRows = 500
	}
	if maxRows > 5000 {
		maxRows = 5000
	}
	trimmed := strings.TrimSpace(*sqlText)
	fields := strings.Fields(trimmed)
	if len(fields) == 0 {
		fail("empty query")
	}
	keyword := strings.ToUpper(strings.TrimPrefix(fields[0], "("))
	if strings.HasPrefix(fields[0], "(") {
		keyword = "SELECT"
	}
	if !readKeywords[keyword] {
		fail("only read-only queries are allowed (SELECT, SHOW, DESCRIBE, EXPLAIN, WITH, ...)")
	}
	if strings.Contains(trimmed, ";") {
		tail := strings.TrimSpace(trimmed[strings.LastIndex(trimmed, ";")+1:])
		if tail != "" {
			fail("only a single statement is allowed")
		}
	}
	p := findProfile(*name)
	database := *db
	if database == "" {
		database = p.Database
	}
	handle := open(p, database)
	defer handle.Close()
	cols, raw, truncated, err := fetchPage(handle, trimmed, nil, maxRows)
	if err != nil {
		fail("%v", err)
	}
	emitRows(cols, raw, int64(len(raw)), 0, maxRows, truncated)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: omysql-engine <profiles|profile|dbs|tables|rows|query> [flags]")
		os.Exit(2)
	}
	cmd := os.Args[1]
	switch cmd {
	case "profiles":
		cmdProfiles()
	case "profile":
		if len(os.Args) < 3 {
			fail("usage: omysql-engine profile <get|save|remove> [flags]")
		}
		switch os.Args[2] {
		case "get":
			fs := flag.NewFlagSet("profile get", flag.ExitOnError)
			cmdProfileGet(fs)
		case "save":
			fs := flag.NewFlagSet("profile save", flag.ExitOnError)
			cmdProfileSave(fs)
		case "remove":
			fs := flag.NewFlagSet("profile remove", flag.ExitOnError)
			cmdProfileRemove(fs)
		default:
			fail("unknown profile action %q", os.Args[2])
		}
	case "dbs":
		fs := flag.NewFlagSet("dbs", flag.ExitOnError)
		cmdDbs(fs)
	case "tables":
		fs := flag.NewFlagSet("tables", flag.ExitOnError)
		cmdTables(fs)
	case "rows":
		fs := flag.NewFlagSet("rows", flag.ExitOnError)
		cmdRows(fs)
	case "query":
		fs := flag.NewFlagSet("query", flag.ExitOnError)
		cmdQuery(fs)
	default:
		fail("unknown command %q", cmd)
	}
}
