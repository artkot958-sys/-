#!/usr/bin/env node
/**
 * Проверка порядка объявления локальных функций.
 *
 * В Lua `local function foo()` создаёт переменную foo в момент выполнения строки.
 * Если вызвать foo() раньше этой строки — получишь "attempt to call a nil value".
 *
 * Этот скрипт ищет случаи, когда локальная функция вызывается в тексте
 * ВЫШЕ места её объявления (учитывая область видимости тела другой функции:
 * тело функции выполнится позже, поэтому вызов внутри другого function ... end
 * не считается ошибкой).
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "src");

function collectLuaFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectLuaFiles(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

let problems = 0;

for (const file of collectLuaFiles(ROOT).sort()) {
  const relative = path.relative(path.join(__dirname, ".."), file);
  const lines = fs.readFileSync(file, "utf8").split("\n");

  // Собираем объявления локальных функций: имя -> номер строки (1-based)
  const declarations = new Map();
  lines.forEach((line, index) => {
    const match = /^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/.exec(line);
    if (match) {
      if (!declarations.has(match[1])) {
        declarations.set(match[1], index + 1);
      }
    }
  });

  if (declarations.size === 0) continue;

  // Отслеживаем глубину блоков function ... end, чтобы понять,
  // находимся ли мы внутри тела функции (код там выполнится позже).
  let blockDepth = 0;
  const depthAtLine = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    depthAtLine[i] = blockDepth;

    // Грубый подсчёт: function/if/for/while/do открывают блок, end закрывает.
    // Нам важны только "function" и "end" верхнего уровня.
    const code = line.replace(/--.*$/, "");

    const opensFunction = /\bfunction\b/.test(code);
    const opensBlock = /\b(if|for|while)\b/.test(code) && /\bthen\b|\bdo\b/.test(code);
    const doBlock = /^\s*do\b/.test(code);

    // end закрывает
    const ends = (code.match(/\bend\b/g) || []).length;

    if (opensFunction || opensBlock || doBlock) blockDepth++;
    if (ends > 0) blockDepth = Math.max(0, blockDepth - ends);
  }

  // Теперь ищем вызовы локальных функций на верхнем уровне выше объявления
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const code = line.replace(/--.*$/, "");

    for (const [name, declarationLine] of declarations) {
      if (i + 1 >= declarationLine) continue; // вызов ниже объявления — ок
      if (depthAtLine[i] !== 0) continue;      // внутри другой функции — ок

      const callRe = new RegExp(`\\b${name}\\s*\\(`, "g");
      if (!callRe.test(code)) continue;

      // не считаем само объявление/присваивание
      if (new RegExp(`function\\s+${name}\\s*\\(`).test(code)) continue;
      if (new RegExp(`local\\s+${name}\\b`).test(code)) continue;

      problems++;
      console.log(`  ⚠️  ${relative}:${i + 1} — вызов ${name}() до объявления (строка ${declarationLine})`);
      console.log(`      ${line.trim().slice(0, 120)}`);
    }
  }
}

console.log("");
if (problems === 0) {
  console.log("✅ Порядок объявления локальных функций в порядке.");
  process.exit(0);
} else {
  console.log(`Найдено проблем: ${problems}`);
  process.exit(1);
}
