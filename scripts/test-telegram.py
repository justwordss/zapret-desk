"""Account-free MTProto req_pq probe against the running local integration.
Reads the local secret without displaying or transmitting it as plain text.
Run with the Telegram build venv's Python (requires cryptography).
"""
import json,os,socket,struct,time,hashlib,argparse
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
ap=argparse.ArgumentParser();ap.add_argument('--config',default=str(Path.home()/'Library/Application Support/ZapretDesk/telegram.json'));ap.add_argument('--dc',type=int,default=4);args=ap.parse_args()
cfg=json.loads(Path(args.config).read_text());secret=bytes.fromhex(cfg['secret'])
header=bytearray(os.urandom(64));header[0]=0x53;header[56:60]=b'\xee'*4;header[60:62]=struct.pack('<h',args.dc)
material=bytes(header[8:56]);enc=Cipher(algorithms.AES(hashlib.sha256(material[:32]+secret).digest()),modes.CTR(material[32:])).encryptor()
wire=enc.update(bytes(header));header[56:64]=wire[56:64]
reverse=material[::-1];dec=Cipher(algorithms.AES(hashlib.sha256(reverse[:32]+secret).digest()),modes.CTR(reverse[32:])).encryptor()
nonce=os.urandom(16);body=struct.pack('<I',0xbe7e8ef1)+nonce
message=b'\0'*8+struct.pack('<Q',int(time.time()*2**32)&~3)+struct.pack('<I',len(body))+body
start=time.monotonic()
with socket.create_connection(('127.0.0.1',cfg['port']),timeout=20) as s:
 s.settimeout(20);s.sendall(header+enc.update(struct.pack('<I',len(message))+message))
 def read(n):
  b=b''
  while len(b)<n:
   chunk=s.recv(n-len(b))
   if not chunk:raise RuntimeError('Proxy closed before MTProto reply')
   b+=chunk
  return dec.update(b)
 n=struct.unpack('<I',read(4))[0]
 if n<40 or n>1048576:raise RuntimeError('Invalid MTProto response length')
 response=read(n)
 assert struct.unpack('<I',response[20:24])[0]==0x05162463,'Expected resPQ'
 assert response[24:40]==nonce,'Nonce mismatch'
print(json.dumps({'ok':True,'test':'MTProto req_pq/resPQ through local TG WS Proxy','dc':args.dc,'ms':round((time.monotonic()-start)*1000)}))
