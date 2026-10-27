"""Read the actual PE resource identity rather than trusting an archive filename."""
import argparse
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
from pathlib import Path
import re

class Fixed(c.Structure):
    _fields_=[(name,w.DWORD) for name in ('signature','structure','fileMS','fileLS','productMS','productLS','flagsMask','flags','os','type','subtype','dateMS','dateLS')]

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--exe',required=True); args=parser.parse_args()
    path=Path(args.exe).resolve(); root=Path(__file__).resolve().parent.parent
    version,code=re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$',(root/'client/pubspec.yaml').read_text('utf-8'),re.M).groups()
    api=c.WinDLL('version',use_last_error=True)
    api.GetFileVersionInfoSizeW.argtypes=[w.LPCWSTR,c.POINTER(w.DWORD)]; api.GetFileVersionInfoSizeW.restype=w.DWORD
    api.GetFileVersionInfoW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,w.LPVOID]; api.GetFileVersionInfoW.restype=w.BOOL
    api.VerQueryValueW.argtypes=[w.LPCVOID,w.LPCWSTR,c.POINTER(w.LPVOID),c.POINTER(w.UINT)]; api.VerQueryValueW.restype=w.BOOL
    ignored=w.DWORD(); size=api.GetFileVersionInfoSizeW(str(path),c.byref(ignored)); assert size
    data=c.create_string_buffer(size); assert api.GetFileVersionInfoW(str(path),0,size,data)
    pointer=w.LPVOID(); length=w.UINT(); assert api.VerQueryValueW(data,'\\',c.byref(pointer),c.byref(length))
    fixed=c.cast(pointer,c.POINTER(Fixed)).contents
    actual=f'{fixed.fileMS>>16}.{fixed.fileMS&65535}.{fixed.fileLS>>16}'
    assert fixed.signature==0xfeef04bd and actual==version and fixed.fileLS&65535==int(code), 'Windows PE version mismatch'
    assert api.VerQueryValueW(data,'\\StringFileInfo\\040904e4\\ProductName',c.byref(pointer),c.byref(length))
    assert c.wstring_at(pointer)=='私有待办', 'Windows product identity mismatch'
    metadata={'versionName':version,'versionCode':int(code),'productName':'私有待办','sha256':hashlib.file_digest(path.open('rb'),'sha256').hexdigest()}
    path.with_suffix('.identity.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n','utf-8')
    print('Verified Windows PE product, actual resource version and SHA256')

if __name__=='__main__': main()
