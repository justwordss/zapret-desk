//go:build darwin

package divert

import "encoding/binary"

// Darwin's bpf_hdr has 18 bytes of fields, while sizeof(struct bpf_hdr)
// includes two bytes of tail padding. bh_hdrlen can be 18 for Ethernet (so
// bh_hdrlen + 14 is aligned). Never reject it by comparing with sizeof.
func bpfRecordAt(buf []byte, off int) (frame []byte, next int, ok bool) {
	const fields = 18
	if off < 0 || off > len(buf)-fields {
		return nil, 0, false
	}
	h := buf[off:]
	caplen := int(binary.NativeEndian.Uint32(h[8:12]))
	hdrlen := int(binary.NativeEndian.Uint16(h[16:18]))
	if hdrlen < fields || hdrlen > len(h) || caplen < 1 || caplen > len(h)-hdrlen {
		return nil, 0, false
	}
	return h[hdrlen : hdrlen+caplen], off + bpfWordAlign(hdrlen+caplen), true
}
