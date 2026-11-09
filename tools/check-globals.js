#!/usr/bin/env node
/**
 * Поиск обращений к неопределённым именам.
 *
 * Ищет идентификаторы, которые используются, но нигде не объявлены:
 *   • local x = ...
 *   • function x()
 *   • параметры функций
 *   • for ... in / for i = ...
 *   • стандартные библиотеки Lua (math, string, table, ...)
 *   • глобальные объекты Roblox (game, workspace, script, task, ...)
 *
 * Ловит опечатки вида `state.caried[player]` (правильно: `state.carried`).
 *
 * Запуск: node tools/check-globals.js
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "src");

const BUILTINS = new Set([
  // Lua
  "assert", "error", "ipairs", "pairs", "next", "print", "select", "tonumber",
  "tostring", "type", "unpack", "setmetatable", "getmetatable", "rawget", "rawset",
  "rawequal", "rawlen", "pcall", "xpcall", "require", "loadstring", "collectgarbage",
  "_G", "_VERSION", "self", "nil", "true", "false",
  // Библиотеки
  "math", "string", "table", "os", "coroutine", "utf8", "bit32", "debug",
  // Roblox
  "game", "workspace", "script", "shared", "task", "wait", "spawn", "delay", "tick",
  "time", "typeof", "Instance", "Enum", "Vector2", "Vector3", "CFrame", "Color3",
  "ColorSequence", "ColorSequenceKeypoint", "NumberSequence", "NumberSequenceKeypoint",
  "UDim", "UDim2", "Rect", "Ray", "Region3", "Random", "TweenInfo", "BrickColor",
  "NumberRange", "PhysicalProperties", "Faces", "Axes", "Font", "OverlapParams",
  "RaycastParams", "DateTime", "warn", "Vector3int16", "Vector2int16", "getfenv", "setfenv",
  "os", "printidentity", "settings", "UserSettings", "version", "ypcall",
]);

const KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto",
  "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
  "until", "while", "continue",
]);

function collectLuaFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectLuaFiles(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

/** Удаляем комментарии и содержимое строк, сохраняя номера строк */
function stripCommentsAndStrings(src) {
  let result = "";
  let i = 0;
  const n = src.length;

  while (i < n) {
    const c = src[i];

    // длинный комментарий --[[ ... ]] или --[==[ ... ]==]
    if (c === "-" && src[i + 1] === "-") {
      const longMatch = /^--\[(=*)\[/.exec(src.slice(i));
      if (longMatch) {
        const closeTag = "]" + longMatch[1] + "]";
        const end = src.indexOf(closeTag, i);
        const stop = end === -1 ? n : end + closeTag.length;
        // сохраняем переводы строк
        result += src.slice(i, stop).replace(/[^\n]/g, " ");
        i = stop;
        continue;
      }
      // строчный комментарий
      let end = src.indexOf("\n", i);
      if (end === -1) end = n;
      result += " ".repeat(end - i);
      i = end;
      continue;
    }

    // длинная строка [[ ... ]]
    if (c === "[" && /^\[(=*)\[/.test(src.slice(i))) {
      const longMatch = /^\[(=*)\[/.exec(src.slice(i));
      const closeTag = "]" + longMatch[1] + "]";
      const end = src.indexOf(closeTag, i);
      const stop = end === -1 ? n : end + closeTag.length;
      result += src.slice(i, stop).replace(/[^\n]/g, " ");
      i = stop;
      continue;
    }

    // обычная строка
    if (c === '"' || c === "'") {
      const quote = c;
      let j = i + 1;
      while (j < n && src[j] !== quote) {
        if (src[j] === "\\") j++;
        j++;
      }
      const stop = Math.min(j + 1, n);
      result += " ".repeat(stop - i);
      i = stop;
      continue;
    }

    // обратные кавычки (интерполяция Luau)
    if (c === "`") {
      let j = i + 1;
      while (j < n && src[j] !== "`") {
        if (src[j] === "\\") j++;
        j++;
      }
      const stop = Math.min(j + 1, n);
      result += " ".repeat(stop - i);
      i = stop;
      continue;
    }

    result += c;
    i++;
  }

  return result;
}

let problems = 0;

for (const file of collectLuaFiles(ROOT).sort()) {
  const relative = path.relative(path.join(__dirname, ".."), file);
  const src = fs.readFileSync(file, "utf8");
  const code = stripCommentsAndStrings(src);
  const lines = code.split("\n");
  const rawLines = src.split("\n");

  const declared = new Set();

  // 1. Собираем все объявления (по всему коду, т.к. конструкции
  //    for ... do и function(...) могут занимать несколько строк)

  const fullCode = lines.join("\n");

  // for i = 1, n do  /  for k, v in pairs(...) do   (многострочные тоже)
  const forRe = /for\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s+(?:=|in)\s/g;
  let forMatch;
  while ((forMatch = forRe.exec(fullCode)) !== null) {
    for (const name of forMatch[1].split(",")) {
      const trimmed = name.trim();
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmed)) declared.add(trimmed);
    }
  }

  // function name(a, b)  и  function(a, b)   (многострочные сигнатуры тоже)
  const fnRe = /function\s*([A-Za-z_][A-Za-z0-9_.]*)?\s*\(([^)]*)\)/g;
  let fnMatch;
  while ((fnMatch = fnRe.exec(fullCode)) !== null) {
    if (fnMatch[1]) declared.add(fnMatch[1].split(".")[0]);
    for (const param of fnMatch[2].split(",")) {
      const clean = param.trim().split(":")[0].trim();
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(clean)) declared.add(clean);
    }
  }

  for (const line of lines) {
    // local a, b, c = ...
    const localMatch = /^\s*local\s+([A-Za-z_][A-Za-z0-9_,\s]*?)(?:\s*=|$)/.exec(line);
    if (localMatch) {
      for (const name of localMatch[1].split(",")) {
        const trimmed = name.trim();
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmed)) declared.add(trimmed);
      }
    }

    // function name(...)  /  local function name(...)
    const fnMatch = /(?:local\s+)?function\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\(([^)]*)\)/.exec(line);
    if (fnMatch) {
      const fnName = fnMatch[1].split(".")[0];
      declared.add(fnName);
      for (const param of fnMatch[2].split(",")) {
        const trimmed = param.trim();
        const clean = trimmed.split(":")[0].trim();
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(clean)) declared.add(clean);
      }
    }

    // анонимная функция в колбэке: function(a, b)
    const anonMatch = /[^.\w]function\s*\(([^)]*)\)/.exec(line);
    if (anonMatch) {
      for (const param of anonMatch[1].split(",")) {
        const clean = param.trim().split(":")[0].trim();
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(clean)) declared.add(clean);
      }
    }

    // for i = 1, n  /  for k, v in pairs()
    const forMatch = /for\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s+(?:=|in)\b/.exec(line);
    if (forMatch) {
      for (const name of forMatch[1].split(",")) {
        const trimmed = name.trim();
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmed)) declared.add(trimmed);
      }
    }
  }

  // 2. Собираем использования: имя, за которым НЕ идёт . : = ( 
  //    (то есть это чтение переменной, а не поле/метод)
  const reported = new Set();

  lines.forEach((line, index) => {
    // убираем назначения и поля
    const re = /(?<![.:\w])([A-Za-z_][A-Za-z0-9_]*)(?![\w.:])/g;
    let match;
    while ((match = re.exec(line)) !== null) {
      const name = match[1];
      const after = line.slice(match.index + name.length).trimStart();

      if (KEYWORDS.has(name)) continue;
      if (BUILTINS.has(name)) continue;
      if (declared.has(name)) continue;
      if (reported.has(name)) continue;

      // Пропускаем имена, за которыми идёт "=" (это назначение поля/глобала)
      if (after.startsWith("=") && !after.startsWith("==")) continue;

      // Пропускаем строки, где имя — часть строки-ключа таблицы  Name = ...
      const before = line.slice(0, match.index);
      if (/[{,]\s*$/.test(before) && after.startsWith("=")) continue;

      reported.add(name);
      problems++;
      console.log(`  ⚠️  ${relative}:${index + 1} — неопределённое имя "${name}"`);
      console.log(`      ${rawLines[index].trim().slice(0, 120)}`);
    }
  });
}

console.log("");
if (problems === 0) {
  console.log("✅ Неопределённых имён не найдено.");
  process.exit(0);
} else {
  console.log(`Найдено потенциальных проблем: ${problems}`);
  process.exit(1);
}
