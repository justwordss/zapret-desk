//go:build darwin

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeskNormalizeDomains(t *testing.T) {
	text, err := normalizeDomains("EXAMPLE.COM\n*.example.com\n^cdn.example.com\n#comment\n")
	if err != nil || text != "^cdn.example.com\nexample.com\n" {
		t.Fatalf("%q %v", text, err)
	}
	for _, bad := range []string{"a..com", "-bad.com", "https://bad.com", "x.com;id", "../../etc/hosts", strings.Repeat("a", 64) + ".com"} {
		if _, err := normalizeDomains(bad); err == nil {
			t.Errorf("accepted %q", bad)
		}
	}
}
func TestDeskRefsTraversal(t *testing.T) {
	for _, ref := range []string{"/etc/hosts", "../secret", "..\\secret"} {
		text := "name='x'\n[[profile]]\n[profile.filter]\nhostlist=['" + ref + "']\n"
		if validateDeskRefs(text) == nil {
			t.Errorf("accepted %q", ref)
		}
	}
	if err := validateDeskRefs("name='ok'\n[[profile]]\n[profile.filter]\nhostlist=['list-general.txt']\n"); err != nil {
		t.Fatal(err)
	}
}
func TestDeskAtomicWrite(t *testing.T) {
	p := filepath.Join(t.TempDir(), "list.txt")
	if err := atomicDeskWrite(p, []byte("a.com\n")); err != nil {
		t.Fatal(err)
	}
	if err := atomicDeskWrite(p, []byte("b.com\n")); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(p)
	if err != nil || string(b) != "b.com\n" {
		t.Fatal(string(b), err)
	}
}
