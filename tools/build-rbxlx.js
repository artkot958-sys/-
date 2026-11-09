#!/usr/bin/env node
/**
 * Собирает готовый файл места Roblox (.rbxlx) из исходников в src/.
 *
 * Что получается: EggGame.rbxlx, который открывается в Roblox Studio
 * двойным кликом — со всеми скриптами уже на своих местах.
 * Ничего копировать вручную не нужно.
 *
 * Запуск: node tools/build-rbxlx.js
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");
const OUTPUT = path.join(ROOT, "EggGame.rbxlx");

let referentCounter = 0;

function nextReferent() {
  referentCounter += 1;
  return `RBX${referentCounter}`;
}

function escapeXml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Обёртка над CDATA: защищает от ]]>, которые могут встретиться в коде */
function cdata(source) {
  return `<![CDATA[${String(source).replace(/]]>/g, "]]]]><![CDATA[>")}]]>`;
}

/**
 * Создаёт <Item>.
 * @param {string} className  класс Roblox
 * @param {string} name       имя объекта
 * @param {string} children   вложенные <Item> (уже собранные)
 * @param {string[]} extraProps дополнительные строки свойств
 */
const SCRIPT_CLASSES = new Set(["Script", "LocalScript", "ModuleScript"]);

function item(className, name, children = "", extraProps = []) {
  const referent = nextReferent();

  const props = [
    `\t\t\t<string name="Name">${escapeXml(name)}</string>`,
    ...extraProps,
  ];

  // Скриптам нужен флаг IsPlugin, иначе Roblox не считает их «обычными» скриптами
  if (SCRIPT_CLASSES.has(className)) {
    props.push(`\t\t\t<bool name="IsPlugin">false</bool>`);
  }

  const lines = [
    `\t<Item class="${className}" referent="${referent}">`,
    `\t\t<Properties>`,
    ...props,
    `\t\t</Properties>`,
  ];

  if (children) {
    lines.push(children);
  }

  lines.push(`\t</Item>`);

  return lines.join("\n");
}

function scriptItem(className, name, source) {
  return item(className, name, "", [
    `\t\t\t<ProtectedString name="Source">${cdata(source)}</ProtectedString>`,
  ]);
}

function read(relativePath) {
  const full = path.join(SRC, relativePath);
  if (!fs.existsSync(full)) {
    throw new Error(`Не найден файл: ${full}`);
  }
  return fs.readFileSync(full, "utf8");
}

// ============================================================
// ИСХОДНИКИ
// ============================================================

const sources = {
  config: read("ReplicatedStorage/EggGameConfig.lua"),
  main: read("ServerScriptService/EggGameMain.server.lua"),
  map: read("ServerScriptService/EggGame/EggGameMap.lua"),
  data: read("ServerScriptService/EggGame/EggGameData.lua"),
  core: read("ServerScriptService/EggGame/EggGameCore.lua"),
  ui: read("StarterPlayer/StarterPlayerScripts/EggGameUI.client.lua"),
};

// ============================================================
// ДЕРЕВО
// ============================================================

// --- ReplicatedStorage ---
const replicatedStorage = item(
  "ReplicatedStorage",
  "ReplicatedStorage",
  scriptItem("ModuleScript", "EggGameConfig", sources.config)
);

// --- ServerScriptService ---
const eggGameFolder = item(
  "Folder",
  "EggGame",
  [
    scriptItem("ModuleScript", "EggGameMap", sources.map),
    scriptItem("ModuleScript", "EggGameData", sources.data),
    scriptItem("ModuleScript", "EggGameCore", sources.core),
  ].join("\n")
);

const serverScriptService = item(
  "ServerScriptService",
  "ServerScriptService",
  [scriptItem("Script", "EggGameMain", sources.main), eggGameFolder].join("\n")
);

// --- StarterPlayer -> StarterPlayerScripts -> LocalScript ---
const starterPlayerScripts = item(
  "StarterPlayerScripts",
  "StarterPlayerScripts",
  scriptItem("LocalScript", "EggGameUI", sources.ui)
);

const starterPlayer = item(
  "StarterPlayer",
  "StarterPlayer",
  starterPlayerScripts
);

// ============================================================
// СБОРКА ФАЙЛА
// ============================================================

const header = `<?xml version="1.0" encoding="utf-8"?>
<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
\t<Meta name="ExplicitAutoJoints">true</Meta>
\t<External>null</External>
\t<External>nil</External>`;

const footer = `</roblox>`;

const xml = [header, replicatedStorage, serverScriptService, starterPlayer, footer].join("\n") + "\n";

fs.writeFileSync(OUTPUT, xml, "utf8");

const sizeKb = (Buffer.byteLength(xml, "utf8") / 1024).toFixed(1);
console.log(`✅ Собрано: ${path.relative(ROOT, OUTPUT)} (${sizeKb} КБ)`);
console.log(`   Объектов: ${referentCounter}`);
console.log("");
console.log("Как открыть:");
console.log("  1. Скачай EggGame.rbxlx");
console.log("  2. Двойной клик — откроется в Roblox Studio");
console.log("  3. Нажми Play (F5)");
