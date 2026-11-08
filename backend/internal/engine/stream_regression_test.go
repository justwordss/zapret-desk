package engine
import("testing";"github.com/naladwepo/zapret-for-mac/internal/proto";"github.com/naladwepo/zapret-for-mac/internal/desync")
func TestEncryptedTLSDoesNotReceiveAnotherFake(t *testing.T){
 s:=loadInline(t,`name="tls"
[window]
tcp=["443"]
[[profile]]
[profile.filter]
proto="tcp"
[[profile.ops]]
op="fake"
fooling=["badseq"]
`)
 e:=New(s,desync.FullCaps(),desync.FakeSet{})
 first:=mkPkt(t,pktSpec{src:mustAddr(t,"192.0.2.2"),dst:mustAddr(t,"198.51.100.2"),sport:45000,dport:443,seq:100,payload:readBlob(t,"tls_clienthello_www_google_com.bin")})
 plan,err:=e.OnTCP(first);if err!=nil || plan==nil || len(plan.Segs)==0{t.Fatalf("no handshake plan: %v",err)}
 encrypted:=mkPkt(t,pktSpec{src:first.Src,dst:first.Dst,sport:first.SrcPort,dport:443,seq:100+uint32(len(first.Payload())),payload:[]byte{0x17,3,3,0,5,1,2,3,4,5}})
 plan,err=e.OnTCP(encrypted);if err!=nil || (plan!=nil && (plan.DropOriginal || len(plan.Segs)>0)){t.Fatal("encrypted application data modified")}
}
func TestRTPAfterSTUNDoesNotReceiveFakes(t *testing.T){
 s:=loadInline(t,`name="voice"
[window]
udp=["19302"]
[[profile]]
[profile.filter]
proto="udp"
l7=["stun"]
[[profile.ops]]
op="fake"
repeats=6
`)
 e:=New(s,desync.FullCaps(),desync.FakeSet{})
 body:=[]byte{0,1,0,0,0x21,0x12,0xa4,0x42,1,2,3,4,5,6,7,8,9,10,11,12}
 p:=mkPkt(t,pktSpec{src:mustAddr(t,"192.0.2.2"),dst:mustAddr(t,"198.51.100.2"),sport:45000,dport:19302,payload:body,udp:true})
 plan,err:=e.OnUDP(p);if err!=nil || plan==nil || len(plan.Dgrams)==0{t.Fatal("STUN did not get a plan")}
 for i:=0;i<100;i++ {
  rtp:=mkPkt(t,pktSpec{src:p.Src,dst:p.Dst,sport:p.SrcPort,dport:p.DstPort,payload:[]byte{0x80,0x78,1,2,3,4,5,6},udp:true})
  plan,err=e.OnUDP(rtp);if err!=nil || (plan!=nil && (plan.DropOriginal || len(plan.Dgrams)>0)){t.Fatalf("voice packet %d was modified",i)}
 }
}
func TestTelegramHandshakeIsProtectedFromBroadStrategies(t *testing.T){
 s:=loadInline(t,`name="broad"
[window]
tcp=["443"]
[[profile]]
[profile.filter]
proto="tcp"
[[profile.ops]]
op="fake"
fooling=["badseq"]
`)
 e:=New(s,desync.FullCaps(),desync.FakeSet{})
 hello:=proto.ModifyTLSFake(readBlob(t,"tls_clienthello_www_google_com.bin"),proto.TLSMod{SNI:"kws4.web.telegram.org"})
 p:=mkPkt(t,pktSpec{src:mustAddr(t,"192.0.2.2"),dst:mustAddr(t,"198.51.100.2"),sport:45000,dport:443,seq:100,payload:hello})
 plan,err:=e.OnTCP(p);if err!=nil || plan!=nil {t.Fatal("Telegram TLS modified by unrelated strategy")}
}
