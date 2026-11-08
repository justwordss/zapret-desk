from pathlib import Path
import struct,sys
root=Path(sys.argv[1]); output=Path(sys.argv[2])
types={'icp4':'icon_16x16.png','icp5':'icon_32x32.png','icp6':'icon_32x32@2x.png','ic07':'icon_128x128.png','ic08':'icon_256x256.png','ic09':'icon_512x512.png','ic10':'icon_512x512@2x.png','ic11':'icon_16x16@2x.png','ic12':'icon_32x32@2x.png','ic13':'icon_128x128@2x.png','ic14':'icon_256x256@2x.png'}
entries=[]
for kind,name in types.items():
 data=(root/name).read_bytes();entries.append(kind.encode()+struct.pack('>I',len(data)+8)+data)
payload=b''.join(entries);output.write_bytes(b'icns'+struct.pack('>I',len(payload)+8)+payload)
