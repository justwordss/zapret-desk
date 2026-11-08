package desync
import("testing";"bytes";"github.com/naladwepo/zapret-for-mac/internal/proto")
func TestDeskUnknownTCPFakeSequence(t *testing.T){
 payload:=[]byte{1,2,3,4,5,6}; c:=injCtx(t,proto.IPProtoTCP,"1.2.3.4",payload)
 params:=OpParams{AnyProtocol:true,FakeUnknownTCP:[][]byte{{0xaa,0xbb},{0xcc,0xdd}},Repeats:6,TTL:3}
 p:=injRun(t,FullCaps(),c,params,&fakeOp{})
 injWantKinds(t,injKinds(p),[]SegKind{SegFake,SegFake,SegData})
 if !bytes.Equal(p.Segs[0].Data,[]byte{0xaa,0xbb}) || !bytes.Equal(p.Segs[1].Data,[]byte{0xcc,0xdd}) || !bytes.Equal(p.Segs[2].Data,payload){t.Fatal("fake order or original payload changed")}
 if p.Segs[0].Repeats!=6 || p.Segs[1].TTL!=3 || p.Segs[2].TTL!=0 {t.Fatal("fake decorations leaked to original")}
}
