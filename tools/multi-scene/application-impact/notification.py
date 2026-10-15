"""Run-unique recorder readiness through the public libnotify file-descriptor API."""
import ctypes
import os
import select
import struct
import time
from contract import require


class Notification:
    def __init__(self, name):
        self.name=name;self.token=ctypes.c_int(-1);self.fd=ctypes.c_int(-1)
        self.lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib')
        self.lib.notify_register_file_descriptor.argtypes=[ctypes.c_char_p,ctypes.POINTER(ctypes.c_int),ctypes.c_int,ctypes.POINTER(ctypes.c_int)]
        self.lib.notify_register_file_descriptor.restype=ctypes.c_uint32
        self.lib.notify_cancel.argtypes=[ctypes.c_int];self.lib.notify_cancel.restype=ctypes.c_uint32
        require(self.lib.notify_register_file_descriptor(name.encode(),ctypes.byref(self.fd),0,ctypes.byref(self.token))==0,'cannot register recorder readiness')
        self.registered_at=time.time();self.consumed=False

    def wait(self, deadline, recorder):
        require(not self.consumed,'recorder readiness already consumed')
        while time.time()<deadline:
            require(recorder.poll() is None,'recorder exited before readiness')
            readable,_,_=select.select([self.fd.value],[],[],max(0,min(0.1,deadline-time.time())))
            if readable:
                data=os.read(self.fd.value,4)
                require(len(data)==4 and struct.unpack('!I',data)[0]==self.token.value,'foreign recorder notification')
                require(time.time()<deadline,'late recorder readiness')
                self.consumed=True
                return dict(name=self.name,token=self.token.value,registered_at=self.registered_at,received_at=time.time())
        raise ValueError('recorder readiness deadline expired')

    def close(self):
        if self.token.value>=0:
            require(self.lib.notify_cancel(self.token.value)==0,'cannot close recorder readiness');self.token.value=-1
