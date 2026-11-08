package lists

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDeskEmptyUserListDoesNotMatchAll(t *testing.T) {
	dir := t.TempDir()
	for _, n := range []string{"list-general-user.txt", "list-exclude-user.txt"} {
		p := filepath.Join(dir, n)
		if err := os.WriteFile(p, []byte("# empty user list\n"), 0600); err != nil {
			t.Fatal(err)
		}
		hs := NewHostSet()
		if err := hs.LoadFile(p); err != nil {
			t.Fatal(err)
		}
		if hs.Match("unrelated.com") {
			t.Fatalf("%s matched everything", n)
		}
	}
	p := filepath.Join(dir, "list-general.txt")
	_ = os.WriteFile(p, []byte("example.com\n"), 0600)
	s := NewSet(dir)
	hs, err := s.Hosts("list-general.txt", "list-general-user.txt")
	if err != nil {
		t.Fatal(err)
	}
	if !hs.Match("sub.example.com") || hs.Match("unrelated.com") {
		t.Fatal("empty user list changed base matching")
	}
}
func TestDeskExactDomain(t *testing.T) {
	s := NewHostSet()
	s.Add("^example.com")
	if !s.Match("example.com") || !s.Match("EXAMPLE.COM") || s.Match("sub.example.com") {
		t.Fatal("exact domain did not stay exact")
	}
	s.Add("example.com")
	if !s.Match("sub.example.com") {
		t.Fatal("suffix domain lost")
	}
}
