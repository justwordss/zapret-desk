package proto

// QUICAssembler retains only authenticated Initial CRYPTO frames, per flow.
// CID changes reset it. It never delays or rewrites a datagram.
type QUICAssembler struct {
	cid     string
	frames  []byte
	packets int
}

func (a *QUICAssembler) Add(payload []byte) (string, bool) {
	h, ok := parseQUICInitial(payload)
	if !ok {
		return "", false
	}
	cid := string(h.dcid)
	if a.cid != cid {
		*a = QUICAssembler{cid: cid}
	}
	if a.packets >= 16 {
		return "", false
	}
	plain, ok := quicDecryptInitial(payload)
	if !ok {
		return "", false
	}
	return a.addPlain(plain)
}
func (a *QUICAssembler) addPlain(plain []byte) (string, bool) {
	frames := quicCryptoOnly(plain)
	if len(a.frames)+len(frames) > 32768 || a.packets >= 16 {
		return "", false
	}
	a.packets++
	a.frames = append(a.frames, frames...)
	hs, ok := quicCryptoStream(a.frames)
	if !ok {
		return "", false
	}
	host, ok := quicHostFromHandshake(hs)
	if ok {
		a.frames = nil
	}
	return host, ok
}
func quicCryptoOnly(plain []byte) (out []byte) {
	for off := 0; off < len(plain); {
		start := off
		kind, n, ok := quicVarint(plain[off:])
		if !ok {
			return
		}
		off += n
		switch kind {
		case 0, 1:
		case 2, 3:
			n, ok := quicSkipACK(plain[off:], kind == 3)
			if !ok {
				return
			}
			off += n
		case 6:
			offset, n, ok := quicVarint(plain[off:])
			if !ok {
				return
			}
			off += n
			size, n, ok := quicVarint(plain[off:])
			if !ok {
				return
			}
			off += n
			if offset > 32768 || size > 32768-offset || size > uint64(len(plain)-off) {
				return
			}
			off += int(size)
			out = append(out, plain[start:off]...)
		default:
			return
		}
	}
	return
}
