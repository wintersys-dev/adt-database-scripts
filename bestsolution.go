Here is the complete, production-hardened Go solution, split into modular files so every block fits cleanly on screen.
It includes all production safeguards:
• Fail-fast checkpoint validation + a built-in --init flag to safely seed replication_checkpoint across targets.
• Memory buffer cap (50,000 transactions) so a prolonged target outage exits cleanly rather than causing an OOM crash.
• 25-second per-target query timeouts so one hung network connection never blocks healthy targets indefinitely.
• Primary-key fallback (matches all non-JSON/non-BLOB before columns if a table lacks an explicit PRIMARY KEY).
• Full JSON, GEOMETRY (spatial SRID + WKB), and BLOB/BINARY support + Linode CA certificate verification.

1. Project Setup (bash)

The Cleanest Way to Install the Dependencies

Once you have saved config.go, handler.go, applier.go, and main.go inside /opt/binlog_sync, run these three commands:
bash
cd /opt/binlog_sync
go mod init binlog-fanout
go mod tidy

2. Configuration Files (source.json & targets.json)


/opt/binlog_sync/source.json

json
{
  "host": "://aivencloud.com",
  "port": 25060,
  "user": "avnadmin",
  "passwd": "SOURCE_PASSWORD",
  "ca_cert_path": "/opt/binlog_sync/ca.pem",
  "schema": "app_db",
  "only_tables": ["users", "orders", "order_items", "payments"],
  "server_id": 99999,
  "batch_interval": 30,
  "max_buffered_txs": 50000
}
Use code with caution.

/opt/binlog_sync/targets.json

json
[
  {
    "name": "linode-target-1",
    "host": "://aivencloud.com",
    "port": 25060,
    "user": "avnadmin",
    "passwd": "TARGET1_PASSWORD",
    "database": "app_db",
    "ca_cert_path": "/opt/binlog_sync/ca.pem"
  },
  {
    "name": "linode-target-2",
    "host": "://aivencloud.com",
    "port": 25060,
    "user": "avnadmin",
    "passwd": "TARGET2_PASSWORD",
    "database": "app_db",
    "ca_cert_path": "/opt/binlog_sync/ca.pem"
  }
]
Use code with caution.

3. Config & TLS Loader (/opt/binlog_sync/config.go)

go
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"os"

	driver "://github.com"
)

type SourceConfig struct {
	Host           string   `json:"host"`
	Port           int      `json:"port"`
	User           string   `json:"user"`
	Passwd         string   `json:"passwd"`
	CACertPath     string   `json:"ca_cert_path"`
	Schema         string   `json:"schema"`
	OnlyTables     []string `json:"only_tables"`
	ServerID       uint32   `json:"server_id"`
	BatchInterval  int      `json:"batch_interval"`
	MaxBufferedTxs int      `json:"max_buffered_txs"`
}

type TargetConfig struct {
	Name       string `json:"name"`
	Host       string `json:"host"`
	Port       int    `json:"port"`
	User       string `json:"user"`
	Passwd     string `json:"passwd"`
	Database   string `json:"database"`
	CACertPath string `json:"ca_cert_path"`
}

func buildTLSConfig(caPath string) (*tls.Config, error) {
	if caPath == "" {
		return &tls.Config{InsecureSkipVerify: true}, nil
	}
	pem, err := os.ReadFile(caPath)
	if err != nil {
		return nil, fmt.Errorf("read CA cert %s: %w", caPath, err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pem) {
		return nil, fmt.Errorf("failed to parse CA cert %s", caPath)
	}
	return &tls.Config{RootCAs: pool}, nil
}

func loadConfigs(srcPath, tgtPath string) (SourceConfig, []TargetConfig, *tls.Config, error) {
	var src SourceConfig
	var targets []TargetConfig

	srcBytes, err := os.ReadFile(srcPath)
	if err != nil {
		return src, nil, nil, err
	}
	if err := json.Unmarshal(srcBytes, &src); err != nil {
		return src, nil, nil, err
	}
	if src.MaxBufferedTxs <= 0 {
		src.MaxBufferedTxs = 50000
	}

	tgtBytes, err := os.ReadFile(tgtPath)
	if err != nil {
		return src, nil, nil, err
	}
	if err := json.Unmarshal(tgtBytes, &targets); err != nil {
		return src, nil, nil, err
	}

	srcTLS, err := buildTLSConfig(src.CACertPath)
	if err != nil {
		return src, nil, nil, err
	}

	for i, t := range targets {
		tTLS, err := buildTLSConfig(t.CACertPath)
		if err != nil {
			return src, nil, nil, err
		}
		tlsName := fmt.Sprintf("linode-tls-%d", i)
		if err := driver.RegisterTLSConfig(tlsName, tTLS); err != nil {
			return src, nil, nil, err
		}
	}

	return src, targets, srcTLS, nil
}
Use code with caution.

4. Binlog Event & SQL Builder (/opt/binlog_sync/handler.go)

go
package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"strings"
	"sync"

	"://github.com"
	"://github.com"
	"://github.com"
	"://github.com"
)

type Statement struct {
	Query string
	Args  []any
}

type CommittedTx struct {
	Pos   mysql.Position
	Stmts []Statement
}

type BatchHandler struct {
	canal.DummyEventHandler
	mu        sync.Mutex
	currentTx []Statement
	batch     []CommittedTx
}

func formatVal(col schema.TableColumn, val any) (string, []any) {
	if val == nil {
		return "?", []any{nil}
	}
	if col.Type == schema.TYPE_JSON {
		if b, ok := val.([]byte); ok {
			return "?", []any{string(b)}
		}
		if s, ok := val.(string); ok {
			return "?", []any{s}
		}
		raw, _ := json.Marshal(val)
		return "?", []any{string(raw)}
	}
	rawLower := strings.ToLower(col.RawType)
	if rawLower == "geometry" || strings.Contains(rawLower, "point") ||
		strings.Contains(rawLower, "polygon") || strings.Contains(rawLower, "linestring") {
		if b, ok := val.([]byte); ok && len(b) > 4 {
			srid := binary.LittleEndian.Uint32(b[:4])
			return "ST_GeomFromWKB(?, ?)", []any{b[4:], srid}
		}
	}
	return "?", []any{val}
}

func buildWhere(cols []schema.TableColumn, pkIndices []int, row []any) ([]string, []any) {
	var wheres []string
	var args []any

	if len(pkIndices) > 0 {
		for _, pkIdx := range pkIndices {
			ph, a := formatVal(cols[pkIdx], row[pkIdx])
			wheres = append(wheres, fmt.Sprintf("`%s`=%s", cols[pkIdx].Name, ph))
			args = append(args, a...)
		}
		return wheres, args
	}

	// Fallback if table has no explicit PRIMARY KEY
	for idx, col := range cols {
		if col.Type == schema.TYPE_JSON || col.Type == schema.TYPE_MEDIUM_BLOB || col.Type == schema.TYPE_BLOB {
			continue
		}
		if row[idx] == nil {
			wheres = append(wheres, fmt.Sprintf("`%s` IS NULL", col.Name))
		} else {
			ph, a := formatVal(col, row[idx])
			wheres = append(wheres, fmt.Sprintf("`%s`=%s", col.Name, ph))
			args = append(args, a...)
		}
	}
	return wheres, args
}

func (h *BatchHandler) OnRow(e *canal.RowsEvent) error {
	h.mu.Lock()
	defer h.mu.Unlock()

	tbl, cols, pks := e.Table, e.Table.Columns, e.Table.PKColumns

	switch e.Action {
	case canal.InsertAction:
		for _, row := range e.Rows {
			var names, phs []string
			var args []any
			for i, col := range cols {
				names = append(names, "`"+col.Name+"`")
				ph, a := formatVal(col, row[i])
				phs = append(phs, ph)
				args = append(args, a...)
			}
			q := fmt.Sprintf("REPLACE INTO `%s` (%s) VALUES (%s)",
				tbl.Name, strings.Join(names, ","), strings.Join(phs, ","))
			h.currentTx = append(h.currentTx, Statement{Query: q, Args: args})
		}

	case canal.UpdateAction:
		for i := 0; i < len(e.Rows); i += 2 {
			before, after := e.Rows[i], e.Rows[i+1]
			var sets []string
			var args []any
			for idx, col := range cols {
				ph, a := formatVal(col, after[idx])
				sets = append(sets, fmt.Sprintf("`%s`=%s", col.Name, ph))
				args = append(args, a...)
			}
			wheres, wArgs := buildWhere(cols, pks, before)
			args = append(args, wArgs...)
			q := fmt.Sprintf("UPDATE `%s` SET %s WHERE %s",
				tbl.Name, strings.Join(sets, ","), strings.Join(wheres, " AND "))
			h.currentTx = append(h.currentTx, Statement{Query: q, Args: args})
		}

	case canal.DeleteAction:
		for _, row := range e.Rows {
			wheres, args := buildWhere(cols, pks, row)
			q := fmt.Sprintf("DELETE FROM `%s` WHERE %s", tbl.Name, strings.Join(wheres, " AND "))
			h.currentTx = append(h.currentTx, Statement{Query: q, Args: args})
		}
	}
	return nil
}

func (h *BatchHandler) OnPosSynced(_ *replication.EventHeader, pos mysql.Position, _ mysql.GTIDSet, _ bool) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if len(h.currentTx) > 0 {
		h.batch = append(h.batch, CommittedTx{Pos: pos, Stmts: h.currentTx})
		h.currentTx = nil
	}
	return nil
}

func (h *BatchHandler) String() string { return "BatchHandler" }
Use code with caution.

5. Target Database & Checkpoint Applier (/opt/binlog_sync/applier.go)

go
package main

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"
	"strings"

	"://github.com"
	driver "://github.com"
)

func openTargetDB(t TargetConfig, tlsIndex int) (*sql.DB, error) {
	cfg := driver.NewConfig()
	cfg.User = t.User
	cfg.Passwd = t.Passwd
	cfg.Net = "tcp"
	cfg.Addr = fmt.Sprintf("%s:%d", t.Host, t.Port)
	cfg.DBName = t.Database
	cfg.TLSConfig = fmt.Sprintf("linode-tls-%d", tlsIndex)
	cfg.ParseTime = true
	return sql.Open("mysql", cfg.FormatDSN())
}

func initCheckpointTable(db *sql.DB) (*mysql.Position, error) {
	_, err := db.Exec(`CREATE TABLE IF NOT EXISTS replication_checkpoint (
		id INT PRIMARY KEY,
		log_file VARCHAR(255) NOT NULL,
		log_pos BIGINT NOT NULL,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
	)`)
	if err != nil {
		return nil, err
	}
	var file string
	var pos uint32
	err = db.QueryRow("SELECT log_file, log_pos FROM replication_checkpoint WHERE id = 1").Scan(&file, &pos)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &mysql.Position{Name: file, Pos: pos}, nil
}

func seedCheckpoint(db *sql.DB, pos mysql.Position) error {
	_, err := db.Exec(`
		INSERT INTO replication_checkpoint (id, log_file, log_pos) VALUES (1, ?, ?)
		ON DUPLICATE KEY UPDATE log_file = VALUES(log_file), log_pos = VALUES(log_pos)`,
		pos.Name, pos.Pos)
	return err
}

func posGreater(a, b mysql.Position) bool {
	numA, _ := strconv.Atoi(strings.Split(a.Name, "."))
	numB, _ := strconv.Atoi(strings.Split(b.Name, "."))
	if numA != numB {
		return numA > numB
	}
	return a.Pos > b.Pos
}

func applyTargetBatch(ctx context.Context, db *sql.DB, txs []CommittedTx, cur *mysql.Position) (*mysql.Position, int, error) {
	var toRun []Statement
	latest := cur
	for _, tx := range txs {
		if cur == nil || posGreater(tx.Pos, *cur) {
			toRun = append(toRun, tx.Stmts...)
			p := tx.Pos
			latest = &p
		}
	}
	if len(toRun) == 0 {
		return cur, 0, nil
	}

	sqlTx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return cur, 0, err
	}
	defer sqlTx.Rollback()

	if _, err := sqlTx.ExecContext(ctx, "SET FOREIGN_KEY_CHECKS = 0"); err != nil {
		return cur, 0, err
	}
	for _, st := range toRun {
		if _, err := sqlTx.ExecContext(ctx, st.Query, st.Args...); err != nil {
			return cur, 0, err
		}
	}
	_, err = sqlTx.ExecContext(ctx, `
		INSERT INTO replication_checkpoint (id, log_file, log_pos) VALUES (1, ?, ?)
		ON DUPLICATE KEY UPDATE log_file = VALUES(log_file), log_pos = VALUES(log_pos)`,
		latest.Name, latest.Pos)
	if err != nil {
		return cur, 0, err
	}
	if _, err := sqlTx.ExecContext(ctx, "SET FOREIGN_KEY_CHECKS = 1"); err != nil {
		return cur, 0, err
	}
	return latest, len(toRun), sqlTx.Commit()
}
Use code with caution.

6. Main Orchestrator (/opt/binlog_sync/main.go)

go
package main

import (
	"context"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"://github.com"
	"://github.com"
)

func main() {
	initMode := flag.Bool("init", false, "Initialize missing target checkpoints from current source position and exit")
	flag.Parse()

	src, targets, srcTLS, err := loadConfigs("/opt/binlog_sync/source.json", "/opt/binlog_sync/targets.json")
	if err != nil {
		log.Fatal(err)
	}

	cfg := canal.NewDefaultConfig()
	cfg.Addr = fmt.Sprintf("%s:%d", src.Host, src.Port)
	cfg.User = src.User
	cfg.Password = src.Passwd
	cfg.ServerID = src.ServerID
	cfg.TLSConfig = srcTLS
	cfg.Dump.ExecutionPath = ""

	for _, tbl := range src.OnlyTables {
		cfg.IncludeTableRegex = append(cfg.IncludeTableRegex, fmt.Sprintf("^%s\\.%s$", src.Schema, tbl))
	}

	c, err := canal.NewCanal(cfg)
	if err != nil {
		log.Fatal(err)
	}

	dbs := make(map[string]*sql.DB)
	checkpoints := make(map[string]*mysql.Position)
	var earliest *mysql.Position

	for i, t := range targets {
		db, err := openTargetDB(t, i)
		if err != nil {
			log.Fatalf("[%s] connect failed: %v", t.Name, err)
		}
		dbs[t.Name] = db

		cp, err := initCheckpointTable(db)
		if err != nil {
			log.Fatalf("[%s] checkpoint table error: %v", t.Name, err)
		}

		if cp == nil {
			if *initMode {
				masterPos, err := c.GetMasterPos()
				if err != nil {
					log.Fatalf("[%s] failed to fetch source position: %v", t.Name, err)
				}
				if err := seedCheckpoint(db, masterPos); err != nil {
					log.Fatalf("[%s] failed to seed checkpoint: %v", t.Name, err)
				}
				cp = &masterPos
				log.Printf("[%s] Seeded initial checkpoint at %s:%d", t.Name, cp.Name, cp.Pos)
			} else {
				log.Fatalf("[%s] missing checkpoint; run with --init or seed replication_checkpoint first", t.Name)
			}
		}

		checkpoints[t.Name] = cp
		log.Printf("[%s] Active checkpoint: %s:%d", t.Name, cp.Name, cp.Pos)
		if earliest == nil || posGreater(*earliest, *cp) {
			earliest = cp
		}
	}

	if *initMode {
		log.Println("Initialization complete.")
		return
	}

	handler := &BatchHandler{}
	c.SetEventHandler(handler)

	go func() {
		log.Printf("Resuming binlog stream from %s:%d", earliest.Name, earliest.Pos)
		if runErr := c.RunFrom(*earliest); runErr != nil {
			log.Fatalf("Canal stream stopped: %v", runErr)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	ticker := time.NewTicker(time.Duration(src.BatchInterval) * time.Second)
	defer ticker.Stop()

	flush := func() {
		handler.mu.Lock()
		if len(handler.batch) > src.MaxBufferedTxs {
			log.Fatalf("Buffered transactions (%d) exceeded limit (%d); exiting to prevent OOM",
				len(handler.batch), src.MaxBufferedTxs)
		}
		if len(handler.batch) == 0 {
			handler.mu.Unlock()
			return
		}
		snapshot := make([]CommittedTx, len(handler.batch))
		copy(snapshot, handler.batch)
		handler.mu.Unlock()

		var wg sync.WaitGroup
		var mu sync.Mutex
		allOK := true

		for _, t := range targets {
			wg.Add(1)
			go func(tc TargetConfig) {
				defer wg.Done()
				ctxTimeout, cancel := context.WithTimeout(context.Background(), 25*time.Second)
				defer cancel()

				newCP, count, err := applyTargetBatch(ctxTimeout, dbs[tc.Name], snapshot, checkpoints[tc.Name])
				mu.Lock()
				defer mu.Unlock()
				if err != nil {
					allOK = false
					log.Printf("[%s] Failed (will retry): %v", tc.Name, err)
				} else {
					checkpoints[tc.Name] = newCP
					log.Printf("[%s] Applied %d rows -> %s:%d", tc.Name, count, newCP.Name, newCP.Pos)
				}
			}(t)
		}
		wg.Wait()

		if allOK {
			handler.mu.Lock()
			handler.batch = handler.batch[len(snapshot):]
			handler.mu.Unlock()
		}
	}

	for {
		select {
		case <-ticker.C:
			flush()
		case <-ctx.Done():
			log.Println("Shutting down; flushing final batch...")
			flush()
			c.Close()
			return
		}
	}
}
Use code with caution.

7. Build, Seed & Run (bash & systemd)

bash
# 1. Secure configs and compile static binary
cd /opt/binlog_sync
chmod 600 source.json targets.json
go build -o binlog-fanout .

# 2. Seed initial target checkpoints once (after loading mysqldump)
./binlog-fanout --init
Use code with caution.
Create /etc/systemd/system/linode-binlog-sync.service:
ini
[Unit]
Description=Linode Managed MySQL 30s Binlog Fan-Out (Go)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/binlog_sync
ExecStart=/opt/binlog_sync/binlog-fanout
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
Use code with caution.
Enable and monitor:
bash
sudo systemctl daemon-reload
sudo systemctl enable --now linode-binlog-sync
sudo journalctl -u linode-binlog-sync -f
Use code with caution.
Everything is compiled into a self-contained binary with TLS verification, --init checkpoint seeding, OOM protection, and per-target timeouts. Let me know if you'd like to add webhook failure notifications or Prometheus metrics.
