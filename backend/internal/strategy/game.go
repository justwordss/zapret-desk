package strategy

import (
	"fmt"
	"strings"
)

// Only ports explicitly marked as batch game placeholders are overridden.
// Operations, domain/IP lists and ordinary ports remain exactly as imported.
func applyGameMode(f *File, mode string) error {
	if mode == "" {
		return nil
	}
	if mode != "off" && mode != "tcp" && mode != "udp" && mode != "all" {
		return fmt.Errorf("invalid game filter mode %q", mode)
	}
	expand := func(items []string) []string {
		result := make([]string, len(items))
		tcp, udp := "12", "12"
		if mode == "tcp" || mode == "all" {
			tcp = "1024-65535"
		}
		if mode == "udp" || mode == "all" {
			udp = "1024-65535"
		}
		for i, s := range items {
			s = strings.ReplaceAll(s, "%GameFilterTCP%", tcp)
			s = strings.ReplaceAll(s, "%GameFilterUDP%", udp)
			result[i] = strings.ReplaceAll(s, "%GameFilter%", tcp)
		}
		return result
	}
	if len(f.Window.GameTCP) > 0 {
		f.Window.TCP = expand(f.Window.GameTCP)
	}
	if len(f.Window.GameUDP) > 0 {
		f.Window.UDP = expand(f.Window.GameUDP)
	}
	for i := range f.Profiles {
		p := &f.Profiles[i]
		if len(p.Filter.GamePorts) > 0 {
			p.Filter.Ports = expand(p.Filter.GamePorts)
		}
	}
	return nil
}
