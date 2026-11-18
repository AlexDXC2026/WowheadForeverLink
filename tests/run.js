// Runs tests/spec.lua against the addon in a clean Lua state for each client locale.
// Usage: node tests/run.js   (from the repository root or the tests folder)
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const luaparse = require("luaparse");

const addonDir = path.join(__dirname, "..", "WowheadForeverLink");
const toc = fs.readFileSync(path.join(addonDir, "WowheadForeverLink.toc"), "utf8");
const files = toc.split(/\r?\n/).filter((l) => l.trim() && !l.startsWith("#")).map((l) => path.join(addonDir, l.trim()));

for (const f of files) luaparse.parse(fs.readFileSync(f, "utf8"), { luaVersion: "5.1" });
console.log("OK Lua 5.1 syntax: " + files.map((f) => path.basename(f)).join(", "));

const spec = fs.readFileSync(path.join(__dirname, "spec.lua"));
const cases = [
  ["esES", "https://www.wowhead.com/forever/es/"],
  ["enUS", "https://www.wowhead.com/forever/"],
  ["deDE", "https://www.wowhead.com/forever/de/"],
  ["zhTW", "https://www.wowhead.com/forever/tw/"],
];
let failed = false;
for (const [locale, base] of cases) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const setGlobal = (k, v) => { lua.lua_pushstring(L, to_luastring(v)); lua.lua_setglobal(L, to_luastring(k)); };
  setGlobal("LOCALE", locale);
  setGlobal("EXPECTED_BASE", base);
  lua.lua_createtable(L, files.length, 0);
  files.forEach((f, i) => { lua.lua_pushstring(L, to_luastring(f)); lua.lua_rawseti(L, -2, i + 1); });
  lua.lua_setglobal(L, to_luastring("ADDON_FILES"));
  if (lauxlib.luaL_loadbuffer(L, spec, spec.length, to_luastring("@spec.lua")) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.log("FAIL [" + locale + "] " + lua.lua_tojsstring(L, -1));
    failed = true;
  } else {
    console.log("OK [" + locale + "] all tests passed");
  }
}
process.exit(failed ? 1 : 0);
