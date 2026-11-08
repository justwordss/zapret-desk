//go:build darwin

package main

import (
	"fmt"
	"github.com/BurntSushi/toml"
	"github.com/naladwepo/zapret-for-mac/internal/ctl"
	"github.com/naladwepo/zapret-for-mac/internal/desync"
	"github.com/naladwepo/zapret-for-mac/internal/strategy"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
)

var deskMu sync.Mutex
var domainRE = regexp.MustCompile(`^(\^)?[a-z0-9]([a-z0-9.-]*[a-z0-9])?$`)

func normalizeDomains(text string) (string, error) {
	if len(text) > 200000 {
		return "", fmt.Errorf("domain list exceeds 200 KB")
	}
	seen := map[string]bool{}
	for _, line := range strings.Split(text, "\n") {
		s := strings.ToLower(strings.TrimSpace(strings.SplitN(line, "#", 2)[0]))
		if s == "" {
			continue
		}
		s = strings.TrimPrefix(s, "*.")
		s = strings.TrimSuffix(s, ".")
		if len(s) > 254 || !domainRE.MatchString(s) || !strings.Contains(s, ".") {
			return "", fmt.Errorf("invalid domain: %s", s)
		}
		for _, label := range strings.Split(strings.TrimPrefix(s, "^"), ".") {
			if len(label) == 0 || len(label) > 63 || strings.HasPrefix(label, "-") || strings.HasSuffix(label, "-") {
				return "", fmt.Errorf("invalid domain: %s", s)
			}
		}
		seen[s] = true
	}
	var lines []string
	for s := range seen {
		lines = append(lines, s)
	}
	sort.Strings(lines)
	return strings.Join(lines, "\n") + "\n", nil
}
func safeRef(s string) bool {
	return s != "" && filepath.Base(s) == s && !strings.ContainsAny(s, "/\\") && s != "." && s != ".."
}
func validateDeskRefs(text string) error {
	var f strategy.File
	if _, err := toml.Decode(text, &f); err != nil {
		return err
	}
	for _, p := range f.Profiles {
		refs := append(append(append(append([]string{}, p.Filter.Hostlist...), p.Filter.HostlistExclude...), p.Filter.IPSet...), p.Filter.IPSetExclude...)
		if p.Filter.HostlistAuto != "" {
			return fmt.Errorf("auto hostlists are not accepted by GUI imports")
		}
		for _, o := range p.Ops {
			refs = append(refs, o.SeqovlPattern, o.Pattern, o.UDPLenPattern, o.Fake.TLS, o.Fake.HTTP, o.Fake.QUIC, o.Fake.SynData)
			refs = append(refs, o.Fake.TLSMulti...)
			refs = append(refs, o.Fake.HTTPMulti...)
			refs = append(refs, o.Fake.QUICMulti...)
			refs = append(refs, o.Fake.UnknownTCP...)
			refs = append(refs, o.Fake.Discord...)
			refs = append(refs, o.Fake.STUN...)
			refs = append(refs, o.Fake.UnknownUDP...)
		}
		for _, ref := range refs {
			if ref != "" && !strings.HasPrefix(ref, "0x") && !safeRef(ref) {
				return fmt.Errorf("unsafe resource reference: %q", ref)
			}
		}
	}
	return nil
}

// Desk exposes only bounded data operations; root never executes imported BATs.
func (d *Daemon) Desk(r ctl.Request) (any, error) {
	deskMu.Lock()
	defer deskMu.Unlock()
	name := r.Arg("name")
	switch r.Cmd {
	case "desk-game-filter":
		old := d.gameMode()
		mode := r.Arg("mode")
		if mode == "" {
			return map[string]string{"mode": old}, nil
		}
		if mode != "off" && mode != "tcp" && mode != "udp" && mode != "all" {
			return nil, fmt.Errorf("invalid game filter mode")
		}
		if err := os.MkdirAll(d.dirs.state, 0755); err != nil {
			return nil, err
		}
		path := filepath.Join(d.dirs.state, "game-filter")
		if err := atomicDeskWrite(path, []byte(mode+"\n")); err != nil {
			return nil, err
		}
		if err := d.Reload(); err != nil {
			_ = atomicDeskWrite(path, []byte(old+"\n"))
			_ = d.Reload()
			return nil, err
		}
		return map[string]string{"mode": mode}, nil

	case "desk-list-read", "desk-list-write":
		allowed := map[string]bool{"list-general-user.txt": true, "list-exclude-user.txt": true}
		if !allowed[name] {
			return nil, fmt.Errorf("list is not editable")
		}
		path := filepath.Join(d.dirs.lists, name)
		if r.Cmd == "desk-list-read" {
			b, err := os.ReadFile(path)
			if os.IsNotExist(err) {
				return map[string]string{"text": ""}, nil
			}
			if err != nil {
				return nil, err
			}
			return map[string]string{"text": string(b)}, nil
		}
		text, err := normalizeDomains(r.Arg("text"))
		if err != nil {
			return nil, err
		}
		old, readErr := os.ReadFile(path)
		if readErr != nil && !os.IsNotExist(readErr) {
			return nil, readErr
		}
		if err = atomicDeskWrite(path, []byte(text)); err != nil {
			return nil, err
		}
		if err = d.Reload(); err != nil {
			_ = atomicDeskWrite(path, old)
			_ = d.Reload()
			return nil, fmt.Errorf("reload failed, restored previous list: %w", err)
		}
		return map[string]string{"text": text}, nil
	case "desk-strategy-install":
		if !safeRef(name) || !strings.HasSuffix(name, ".toml") || len(name) > 160 {
			return nil, fmt.Errorf("invalid strategy filename")
		}
		text := r.Arg("text")
		if len(text) > 500000 {
			return nil, fmt.Errorf("strategy exceeds 500 KB")
		}
		if err := validateDeskRefs(text); err != nil {
			return nil, err
		}
		tmp, err := os.CreateTemp(d.dirs.strategies, ".import-*.tmp")
		if err != nil {
			return nil, err
		}
		path := tmp.Name()
		defer os.Remove(path)
		if _, err = tmp.WriteString(text); err != nil {
			tmp.Close()
			return nil, err
		}
		if err = tmp.Close(); err != nil {
			return nil, err
		}
		s, err := strategy.Load(path, strategy.LoadOpts{ListsDir: d.dirs.lists, GameMode: d.gameMode(), FakesDir: d.dirs.fakes, Caps: desync.FullCaps()})
		if err != nil {
			return nil, err
		}
		if len(s.Unsupported(desync.FullCaps())) > 0 {
			return nil, fmt.Errorf("unsupported operations")
		}
		dest := filepath.Join(d.dirs.strategies, name)
		if _, err = os.Lstat(dest); err == nil {
			return nil, fmt.Errorf("strategy already exists; rename the imported file")
		}
		if err = os.Chmod(path, 0644); err != nil {
			return nil, err
		}
		if err = os.Rename(path, dest); err != nil {
			return nil, err
		}
		return map[string]string{"name": s.Name}, nil
	default:
		return nil, fmt.Errorf("unknown desk command")
	}
}
func atomicDeskWrite(path string, b []byte) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".desk-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(b); err != nil {
		f.Close()
		return err
	}
	if err = f.Chmod(0644); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}

func (d *Daemon) gameMode() string {
	b, err := os.ReadFile(filepath.Join(d.dirs.state, "game-filter"))
	if err != nil {
		return "off"
	}
	m := strings.TrimSpace(string(b))
	if m == "tcp" || m == "udp" || m == "all" {
		return m
	}
	return "off"
}
