//go:build darwin

package divert

import (
	"bytes"
	"encoding/binary"
	"github.com/naladwepo/zapret-for-mac/internal/proto"
	"testing"
)

func recordWithHeader(n int, frame []byte) []byte {
	b := make([]byte, bpfWordAlign(n+len(frame)))
	binary.NativeEndian.PutUint32(b[8:12], uint32(len(frame)))
	binary.NativeEndian.PutUint32(b[12:16], uint32(len(frame)))
	binary.NativeEndian.PutUint16(b[16:18], uint16(n))
	copy(b[n:], frame)
	return b
}
func TestBPFRecordAccepts18ByteEthernetHeader(t *testing.T) {
	p := mkPkt(t, proto.Tmpl{Src: testDst4, Dst: testSrc4, SrcPort: 443, DstPort: 45000, Seq: 7, Ack: 9, Flags: proto.TCPAck, Payload: []byte("response")})
	frame := make([]byte, 14)
	binary.BigEndian.PutUint16(frame[12:14], ethTypeIPv4)
	frame = append(frame, p.Raw...)
	for _, n := range []int{18, 20, 22} {
		b := recordWithHeader(n, frame)
		b = append(b, recordWithHeader(n, frame)...)
		var o observer
		count := 0
		for off := 0; off < len(b); {
			f, next, ok := bpfRecordAt(b, off)
			if !ok {
				t.Fatal("rejected valid record", n)
			}
			if !bytes.Equal(f, frame) {
				t.Fatal("frame offset corrupted")
			}
			o.handleFrame(f, func(got *proto.Pkt) {
				count++
				if got.SrcPort != 443 {
					t.Fatal("bad port")
				}
			})
			off = next
		}
		if count != 2 {
			t.Fatal("records not observed", n, count)
		}
	}
}
func TestBPFRecordRejectsTruncationAndInvalidLength(t *testing.T) {
	b := recordWithHeader(18, []byte{1, 2, 3, 4})
	for n := 0; n < 22; n++ {
		if _, _, ok := bpfRecordAt(b[:n], 0); ok {
			t.Fatal("accepted truncated record", n)
		}
	}
	binary.NativeEndian.PutUint32(b[8:12], 0xffffffff)
	if _, _, ok := bpfRecordAt(b, 0); ok {
		t.Fatal("accepted overflowing length")
	}
}
