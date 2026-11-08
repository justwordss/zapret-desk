package divert
import("testing";"bytes";"encoding/binary";"time";"github.com/naladwepo/zapret-for-mac/internal/proto")
func longHello()[]byte {b:=make([]byte,2500);copy(b,[]byte{0x16,3,3,0,0,1});binary.BigEndian.PutUint16(b[3:5],uint16(len(b)-5));for i:=9;i<len(b);i++{b[i]=byte(i)};return b}
func helloPart(t *testing.T,b []byte,offset int)*proto.Pkt{return mkPkt(t,proto.Tmpl{Src:testSrc4,Dst:testDst4,SrcPort:45000,DstPort:443,Seq:100+uint32(offset),Ack:50,Flags:proto.TCPAck,Window:1234,Payload:b})}
func TestHelloQueueReassemblesOutOfOrder(t *testing.T){
 var q helloQueue;now:=time.Now();hello:=longHello()
 if b,_,wait:=q.push(helloPart(t,hello[:1000],0),now);!wait || b!=nil{t.Fatal("first fragment not held")}
 if _,_,wait:=q.push(helloPart(t,hello[2000:],2000),now);!wait{t.Fatal("gap not held")}
 b,flush,wait:=q.push(helloPart(t,hello[1000:2000],1000),now)
 if wait || len(flush)>0 || b==nil{t.Fatal("hello not released")};p,err:=proto.Parse(b);if err!=nil || !bytes.Equal(p.Payload(),hello) || p.Seq!=100 || p.Window!=1234 {t.Fatal("stream bytes/header changed")}
 parts,_:=splitTCPForMTU(b,1280);var joined []byte
 for i,part:=range parts {p,_:=proto.Parse(part);if len(part)>1280 || p.Seq!=100+uint32(len(joined)) || proto.L4Checksum(p.Src,p.Dst,p.Proto,part[p.L3Len:])!=0xffff{t.Fatalf("bad segment %d",i)};joined=append(joined,p.Payload()...)}
 if !bytes.Equal(joined,hello){t.Fatal("MTU segmentation corrupted stream")}
}
func TestHelloQueueTimeoutForwardsOriginal(t *testing.T){
 var q helloQueue;p:=helloPart(t,longHello()[:900],0);now:=time.Now();q.push(p,now)
 if q.expire(now.Add(helloWait-time.Millisecond))!=nil{t.Fatal("early timeout")}
 out:=q.expire(now.Add(helloWait));if len(out)!=1 || !bytes.Equal(out[0],p.Raw)||len(q.pending)!=0{t.Fatal("held packet lost on timeout")}
}
func TestHelloQueueLimitsAndRetransmissions(t *testing.T){
 var q helloQueue;h:=longHello();now:=time.Now();p:=helloPart(t,h[:900],0)
 q.push(p,now);q.push(p,now)
 b,_,wait:=q.push(helloPart(t,h[900:],900),now);if wait || b==nil{t.Fatal("retransmission blocked assembly")}
}
