#!/usr/bin/env node
/**
 * Проверка синтаксиса .lua файлов проекта.
 *
 * Что делает:
 *  1. Заменяет Luau-конструкции (compound assignment +=, тип-аннотации, continue,
 *     string interpolation) на обычный Lua 5.1, понятный парсеру luaparse.
 *  2. Парсит получившийся код через luaparse (Lua 5.1 grammar) и сообщает об ошибках.
 *
 * Это НЕ полноценный компилятор Luau, но ловит 95% опечаток: лишние end,
 * незакрытые скобки, битые строки, неправильные ключевые слова.
 *
 * Запуск: node tools/check-syntax.js
 */

const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const ROOT = path.join(__dirname, "..", "src");

function collectLuaFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectLuaFiles(full, out);
    } else if (entry.name.endsWith(".lua")) {
      out.push(full);
    }
  }
  return out;
}

/**
 * Готовим Luau-код к парсингу Lua 5.1.
 * Обрабатываем только то, что реально используется в проекте.
 */
function toLua51(src) {
  let code = src;

  // Убираем комментарии-блоки и строчные комментарии аккуратно (только для анализа)
  // Комментарии не ломают парсинг, поэтому оставляем их как есть.

  // 1. Compound assignment: x += y  ->  x = x + y
  //    Поддерживаем цели вида: Name, Name.Field, Name[expr], Name.Field[expr].Field
  const compoundOps = ["+", "-", "*", "/", "%", "^", ".."];
  for (const op of compoundOps) {
    const escaped = op.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const target =
      "[A-Za-z_][A-Za-z0-9_]*" +            // первый идентификатор
      "(?:\\.[A-Za-z_][A-Za-z0-9_]*|\\[[^\\]\\n]*\\])*"; // .field или [expr]
    const re = new RegExp(
      `^([ \\t]*)(${target})[ \\t]*${escaped}=[ \\t]*(\\S.*)$`,
      "gm"
    );
    code = code.replace(re, (match, indent, lhs, rhs) => {
      // отбрасываем строки с непарными кавычками (грубая защита)
      if ((rhs.match(/"/g) || []).length % 2 !== 0) {
        return match;
      }
      return `${indent}${lhs} = ${lhs} ${op} ${rhs}`;
    });
  }

  // 2. `continue` -> заглушка (в Lua 5.1 его нет)
  code = code.replace(/^([ \t]*)continue\b[ \t]*$/gm, "$1-- continue");

  // 3. string interpolation `...` -> "..." (только простые случаи)
  code = code.replace(/`([^`\\$]*)`/g, '"$1"');

  // 4. Тип-аннотации в объявлениях: local x: Type = ...  /  function f(a: Type): Type
  //    Убираем `: Type` перед = , ) , , а также в параметрах
  code = code.replace(/([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[A-Za-z_][A-Za-z0-9_.<>|{}\[\] ,\\]*\s*=/g, "$1 =");
  code = code.replace(/([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[A-Za-z_][A-Za-z0-9_.<>|{}\[\]]*\s*([,)])/g, "$1$2");

  // 5. `if ... then ... end` с `and` — не трогаем.

  return code;
}

function checkFile(file) {
  const src = fs.readFileSync(file, "utf8");
  const prepared = toLua51(src);

  try {
    luaparse.parse(prepared, {
      luaVersion: "5.1",
      comments: false,
      scope: false,
      locations: true,
      ranges: false,
    });
    return { file, ok: true };
  } catch (error) {
    // Пытаемся определить номер строки из ошибки
    const lineMatch = /\[(\d+):(\d+)\]/.exec(error.message);
    const line = lineMatch ? Number(lineMatch[1]) : null;

    return {
      file,
      ok: false,
      line,
      message: error.message,
      source: line ? src.split("\n")[line - 1] : null,
    };
  }
}

const files = collectLuaFiles(ROOT).sort();
let failed = 0;

console.log(`Проверяю ${files.length} файлов...\n`);

for (const file of files) {
  const result = checkFile(file);
  const relative = path.relative(path.join(__dirname, ".."), file);

  if (result.ok) {
    console.log(`  ✅ ${relative}`);
  } else {
    failed++;
    console.log(`  ❌ ${relative}`);
    console.log(`     ${result.message}`);
    if (result.line) {
      console.log(`     Строка ${result.line}: ${(result.source || "").trim().slice(0, 140)}`);
    }
  }
}

console.log("");

if (failed > 0) {
  console.log(`Провалено файлов: ${failed}`);
  process.exit(1);
} else {
  console.log("Все файлы разобраны без ошибок синтаксиса.");
}
