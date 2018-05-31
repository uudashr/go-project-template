package mysql_test

import (
	"database/sql"
	"flag"
	"fmt"
	"testing"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/mattes/migrate"
	"github.com/mattes/migrate/database/mysql"
	_ "github.com/mattes/migrate/source/file"
)

var (
	scripts             = flag.String("scripts", "file://migrations", "The location of migration scripts.")
	dbUser              = flag.String("db-user", "myproject", "Database username")
	dbPassword          = flag.String("db-password", "secret", "Database password")
	dbAddress           = flag.String("db-address", "localhost:3306", "Database address")
	dbName              = flag.String("db-name", "myproject_test", "Database name")
	dbPingMaxRetry      = flag.Int("db-ping-max-retry", 60, "Database ping max retry")
	dbPingRetryInterval = flag.Duration("db-ping-retry-interval", 1*time.Second, "Database ping retry interval")
)

const driverName = "mysql"

type fixture struct {
	t  *testing.T
	db *sql.DB
}

func setupFixture(t *testing.T) *fixture {
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?multiStatements=true&clientFoundRows=true&parseTime=true&loc=Local", *dbUser, *dbPassword, *dbAddress, *dbName)
	db, err := sql.Open(driverName, dsn)
	if err != nil {
		t.Fatal("err:", err)
	}

	if err = tryPing(db, *dbPingMaxRetry, *dbPingRetryInterval); err != nil {
		t.Fatal("err:", err)
	}

	driver, err := mysql.WithInstance(db, &mysql.Config{})
	if err != nil {
		t.Fatal("err:", err)
	}

	m, err := migrate.NewWithDatabaseInstance(*scripts, driverName, driver)
	if err != nil {
		t.Fatal("err:", err)
	}

	if err := m.Down(); err != nil {
		if err != migrate.ErrNoChange {
			t.Error("Failed execute migration down scripts:", err)
		}
	}

	if err := m.Drop(); err != nil {
		t.Error("Failed execute migration pre-drop:", err)
	}

	if err := m.Up(); err != nil {
		t.Error("Failed execute migration up scripts:", err)
	}

	return &fixture{
		t:  t,
		db: db,
	}
}

func (s *fixture) tearDown() {
	if err := s.db.Close(); err != nil {
		s.t.Error("fail to clise db:", err)
	}
}

func tryPing(db *sql.DB, maxRetry int, interval time.Duration) (err error) {
	maxAttempts := maxRetry + 1
	for i := 0; i < maxAttempts; i++ {
		if err = db.Ping(); err != nil {
			time.Sleep(interval)
			continue
		}
		return nil
	}
	return err
}
