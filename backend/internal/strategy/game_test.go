package strategy

import (
	"github.com/naladwepo/zapret-for-mac/internal/desync"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestGameModeChangesOnlyExplicitPlaceholders(t *testing.T) {
	text := `name="game-test"
[window]
tcp=["80","443","12"]
udp=["443","12"]
game_tcp=["80","443","%GameFilterTCP%"]
game_udp=["443","%GameFilterUDP%"]
[[profile]]
name="website"
[profile.filter]
proto="tcp"
ports=["443"]
hostlist_domains=["example.com"]
[[profile.ops]]
op="fake"
[[profile]]
name="game-tcp"
cutoff="n4"
[profile.filter]
proto="tcp"
ports=["12"]
game_ports=["%GameFilterTCP%"]
[[profile.ops]]
op="fake"
any_protocol=true
[[profile]]
name="game-udp"
cutoff="n4"
[profile.filter]
proto="udp"
ports=["12"]
game_ports=["%GameFilterUDP%"]
[[profile.ops]]
op="fake"
any_protocol=true
`
	p := filepath.Join(t.TempDir(), "game.toml")
	if err := os.WriteFile(p, []byte(text), 0600); err != nil {
		t.Fatal(err)
	}
	var baseline *Strategy
	for _, mode := range []string{"off", "tcp", "udp", "all", "off"} {
		s, err := Load(p, LoadOpts{ListsDir: t.TempDir(), FakesDir: t.TempDir(), Caps: desync.FullCaps(), GameMode: mode})
		if err != nil {
			t.Fatal(err)
		}
		tcp, udp := mode == "tcp" || mode == "all", mode == "udp" || mode == "all"
		if s.WindowTCP.Has(65000) != tcp || s.WindowUDP.Has(65000) != udp || s.Profiles[1].Filter.Ports.Has(65000) != tcp || s.Profiles[2].Filter.Ports.Has(65000) != udp {
			t.Fatal("mode did not update profiles and capture windows", mode)
		}
		if !s.Profiles[0].Filter.Ports.Has(443) || s.Profiles[0].Filter.Ports.Has(65000) || !s.Profiles[0].Filter.Hostlist.Match("example.com") {
			t.Fatal("ordinary filter changed")
		}
		if baseline == nil {
			baseline = s
		} else {
			for i := range s.Profiles {
				if !reflect.DeepEqual(s.Profiles[i].Ops, baseline.Profiles[i].Ops) {
					t.Fatal("operation parameters changed")
				}
			}
		}
	}
	b, _ := os.ReadFile(p)
	if string(b) != text {
		t.Fatal("source strategy was rewritten")
	}
	if _, err := Load(p, LoadOpts{GameMode: "invalid"}); err == nil {
		t.Fatal("invalid mode accepted")
	}
}
