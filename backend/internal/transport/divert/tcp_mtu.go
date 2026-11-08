package divert
import("encoding/binary";"net/netip";"github.com/naladwepo/zapret-for-mac/internal/proto")
func repairChecksums(b []byte,iplen int,src,dst netip.Addr,bad bool){
 binary.BigEndian.PutUint16(b[iplen+16:iplen+18],0)
 sum:=proto.L4Checksum(src,dst,proto.IPProtoTCP,b[iplen:]);if bad {sum^=0xbeaf};binary.BigEndian.PutUint16(b[iplen+16:iplen+18],sum)
}
func splitTCPForMTU(raw []byte,mtu int)([][]byte,error){
 if len(raw)<=mtu{return [][]byte{raw},nil}
 p,err:=proto.Parse(raw);if err!=nil || !p.IsTCP() || (p.L3Len!=20 && p.L3Len!=40){return [][]byte{raw},nil}
 header:=p.L3Len+p.L4Len;max:=mtu-header
 if max<=0 {return [][]byte{raw},nil}
 bad:=proto.L4Checksum(p.Src,p.Dst,p.Proto,raw[p.L3Len:])!=0xffff
 var out [][]byte;body:=p.Payload()
 for offset:=0;offset<len(body);offset+=max {
  end:=offset+max;if end>len(body){end=len(body)}
  b:=append(append([]byte(nil),raw[:header]...),body[offset:end]...)
  binary.BigEndian.PutUint32(b[p.L3Len+4:p.L3Len+8],p.Seq+uint32(offset))
  if end<len(body) {b[p.L3Len+13]&= ^uint8(proto.TCPPsh|proto.TCPFin)}
  if p.Ver==4 {binary.BigEndian.PutUint16(b[4:6],p.IPID+uint16(len(out)))}
  fixPacketLength(b,p.L3Len);repairChecksums(b,p.L3Len,p.Src,p.Dst,bad);out=append(out,b)
 }
 return out,nil
}
