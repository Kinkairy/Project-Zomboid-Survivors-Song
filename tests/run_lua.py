"""Run real Lua modules against explicit engine stubs, not a PZ game test.

Copied from the approved Song recovery payload's tests/run_lua.py. Optional
preloads run in the same Lua state before the case (for existing fixtures).
This runner never downloads a runtime or supplies missing native game files.
CLI: run_lua.py [--library LIB] [--preload FIXTURE] SCRIPT [SCRIPT_ARG ...]
Lua receives arg[0] = SCRIPT and arg[1..N] = SCRIPT_ARG, including in preloads.
"""
import argparse
import ctypes
import ctypes.util
from pathlib import Path

def run(path, library=None, preloads=(), script_args=()):
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
    lua.lua_createtable.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int]
    lua.lua_createtable.restype=None
    lua.lua_pushlstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t]
    lua.lua_pushlstring.restype=ctypes.c_char_p
    lua.lua_rawseti.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_longlong]
    lua.lua_rawseti.restype=None
    lua.lua_setglobal.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    lua.lua_setglobal.restype=None
    lua.lua_close.argtypes=[ctypes.c_void_p]
    state=lua.luaL_newstate()
    if not state: raise RuntimeError('Could not create Lua state')
    try:
        lua.luaL_openlibs(state)
        lua.lua_createtable(state, len(script_args), 1)
        for index, value in enumerate((path, *script_args)):
            encoded=str(value).encode()
            lua.lua_pushlstring(state,encoded,len(encoded))
            lua.lua_rawseti(state,-2,index)
        lua.lua_setglobal(state,b'arg')
        for script in (*preloads, path):
            code=lua.luaL_loadfilex(state,str(script).encode(),None)
            if code==0: code=lua.lua_pcallk(state,0,0,0,0,None)
            if code:
                message=(lua.lua_tolstring(state,-1,None) or b'Lua error').decode()
                raise RuntimeError(f"{script}: {message}")
    finally: lua.lua_close(state)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('script_args', nargs='*', help='arguments available through Lua arg[1..N]')
    parser.add_argument('--library', help='optional Lua 5.4 shared-library path')
    parser.add_argument('--preload', action='append', type=Path, default=[],
                        help='load this file before the case; may be repeated')
    args = parser.parse_intermixed_args()
    run(args.path, args.library, args.preload, args.script_args)
