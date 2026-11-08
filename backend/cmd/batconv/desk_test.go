package main

import (
	"github.com/naladwepo/zapret-for-mac/internal/desync"
	"github.com/naladwepo/zapret-for-mac/internal/strategy"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeskKeepsAllFakePayloads(t *testing.T) {
	src := `start "zapret" winws.exe --wf-tcp=443 --wf-udp=443 --filter-tcp=443 --dpi-desync=fake --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=0x01020304 --dpi-desync-fake-unknown=0xaabb --dpi-desync-fake-unknown=0xccdd`
	gf, _ := GameFilterFor("off")
	r, err := Convert("test.bat", []byte(src), gf)
	if err != nil {
		t.Fatal(err)
	}
	f := r.File.Profiles[0].Ops[0].Fake
	if len(f.TLSMulti) != 2 || len(f.UnknownTCP) != 2 {
		t.Fatalf("lost fake payloads: %+v", f)
	}
	p := filepath.Join(t.TempDir(), "test.toml")
	os.WriteFile(p, []byte(r.Marshal()), 0600)
	s, err := strategy.Load(p, strategy.LoadOpts{Caps: desync.FullCaps()})
	if err != nil {
		t.Fatal(err)
	}
	params := s.Profiles[0].Ops[0].Params
	if len(params.FakeTLSMulti) != 2 || len(params.FakeUnknownTCP) != 2 {
		t.Fatal("loader lost payload list")
	}
	if strings.Contains(r.Marshal(), "schema keeps one") {
		t.Fatal("lossy conversion")
	}
}
