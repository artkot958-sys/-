/**
 * Компиляция исходников настоящим Luau (тем же языком, что в Roblox).
 *
 * Это самый достоверный тест: если Luau не скомпилировал файл,
 * Roblox Studio покажет ошибку — значит, игра не запустится.
 *
 * Запуск: node tools/check-luau.js
 */

import { LuauState } from "luau-web";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");

function collectLuaFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectLuaFiles(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

const state = await LuauState.createAsync();

const files = collectLuaFiles(SRC).sort();
let failed = 0;

console.log(`Компилирую ${files.length} файлов настоящим Luau...\n`);

for (const file of files) {
  const relative = path.relative(ROOT, file);
  const source = fs.readFileSync(file, "utf8");

  const result = state.loadstring(source, "@" + relative, false);

  if (typeof result === "string") {
    failed++;
    console.log(`  ❌ ${relative}`);
    console.log(`     ${result}`);
  } else {
    console.log(`  ✅ ${relative}`);
  }
}

console.log("");

if (failed > 0) {
  console.log(`Не скомпилировалось файлов: ${failed}`);
  console.log("Roblox Studio выдаст эти же ошибки.");
  process.exit(1);
} else {
  console.log("✅ Все файлы компилируются настоящим Luau.");
}
