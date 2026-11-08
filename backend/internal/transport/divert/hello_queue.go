package divert

import (
 "encoding/binary"
 "time"
 "github.com/naladwepo/zapret-for-mac/internal/proto"
 "github.com/naladwepo/zapret-for-mac/internal/desync"
)
const helloLimit=32768
const helloWait=200*time.Millisecond
const helloConnections=128
// Bounded, short-lived ClientHello assembly. All failures release original
// packets unchanged; unrelated flows never wait behind a partial handshake.
type pendingHello struct { first *proto.Pkt; originals [][]byte; data,present []byte; expected,end int; start time.Time }
type helloQueue struct { pending map[desync.FlowKey]*pendingHello }
func helloKey(p *proto.Pkt) desync.FlowKey {return desync.FlowKey{Src:p.Src,Dst:p.Dst,SrcPort:p.SrcPort,DstPort:p.DstPort,Proto:p.Proto}}
func (q *helloQueue) expire(now time.Time) (out [][]byte) {
 for k,h:=range q.pending {if now.Sub(h.start)>=helloWait {out=append(out,h.originals...);delete(q.pending,k)}};return
}
func (q *helloQueue) push(p *proto.Pkt,now time.Time)(ready []byte,flush [][]byte,wait bool){
 k:=helloKey(p);h:=q.pending[k];body:=p.Payload()
 if h==nil {
  if len(body)<9 || body[0]!=0x16 || body[1]!=3 || body[5]!=1 || p.Flags&(proto.TCPSyn|proto.TCPFin|proto.TCPRst)!=0 {return}
  size:=5+int(binary.BigEndian.Uint16(body[3:5]))
  if size<=len(body) || size>helloLimit || len(q.pending)>=helloConnections {return}
  if q.pending==nil {q.pending=make(map[desync.FlowKey]*pendingHello)}
  raw:=append([]byte(nil),p.Raw...);first,_:=proto.Parse(raw)
  h=&pendingHello{first:first,data:make([]byte,helloLimit),present:make([]byte,helloLimit),expected:size,start:now};q.pending[k]=h
 }
 if len(body)==0 && p.Flags&(proto.TCPFin|proto.TCPRst)==0 {return}
 offset:=int(int32(p.Seq-h.first.Seq))
 if offset<0 || offset+len(body)>helloLimit || len(h.originals)>=32 || p.Flags&(proto.TCPSyn|proto.TCPFin|proto.TCPRst)!=0 {
  flush=append(flush,h.originals...);delete(q.pending,k);return
 }
 h.originals=append(h.originals,append([]byte(nil),p.Raw...))
 for i,b:=range body {n:=offset+i;if h.present[n]!=0 && h.data[n]!=b {flush=h.originals;delete(q.pending,k);return nil,flush,true};h.data[n]=b;h.present[n]=1}
 if end:=offset+len(body);end>h.end {h.end=end}
 if h.end<h.expected {return nil,nil,true}
 for _,b:=range h.present[:h.end] {if b==0 {return nil,nil,true}}
 first:=h.first;header:=first.L3Len+first.L4Len
 ready=append(append([]byte(nil),first.Raw[:header]...),h.data[:h.end]...)
 delete(q.pending,k)
 fixPacketLength(ready,first.L3Len)
 // First packet's TCP options, original sequence and stream bytes survive.
 repairChecksums(ready,first.L3Len,first.Src,first.Dst,false)
 return ready,nil,false
}
func fixPacketLength(b []byte,iplen int){
 if b[0]>>4==4 {binary.BigEndian.PutUint16(b[2:4],uint16(len(b)));binary.BigEndian.PutUint16(b[10:12],0);binary.BigEndian.PutUint16(b[10:12],proto.Checksum16(b[:iplen]))} else {binary.BigEndian.PutUint16(b[4:6],uint16(len(b)-40))}
}
