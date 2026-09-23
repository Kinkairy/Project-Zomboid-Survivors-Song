"""Run the real Lua modules against engine stubs; not a PZ game test."""
import ctypes, ctypes.util, sys
from pathlib import Path

def run(path, library=None):
    name=library or ctypes.util.find_library('lua5.4')
    if not name: raise RuntimeError('Lua 5.4 shared library required')
    lua=ctypes.CDLL(name)
    lua.luaL_newstate.restype=ctypes.c_void_p
    lua.luaL_openlibs.argtypes=[ctypes.c_void_p]
    lua.luaL_loadfilex.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p]
    lua.luaL_loadfilex.restype=ctypes.c_int
    lua.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
    lua.lua_pcallk.restype=ctypes.c_int
    lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.POINTER(ctypes.c_size_t)]
    lua.lua_tolstring.restype=ctypes.c_char_p
    lua.lua_close.argtypes=[ctypes.c_void_p]
    state=lua.luaL_newstate()
    if not state: raise RuntimeError('Could not create Lua state')
    try:
        lua.luaL_openlibs(state)
        code=lua.luaL_loadfilex(state,str(path).encode(),None)
        if code==0: code=lua.lua_pcallk(state,0,-1,0,0,None)
        if code: raise RuntimeError((lua.lua_tolstring(state,-1,None) or b'Lua error').decode())
    finally: lua.lua_close(state)
if __name__=='__main__':run(Path(sys.argv[1]),sys.argv[2] if len(sys.argv)>2 else None)
