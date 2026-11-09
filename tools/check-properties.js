#!/usr/bin/env node
/**
 * Проверка имён свойств Roblox, использованных в коде.
 *
 * Ловит опечатки вида `part.Transparancy = 1` или несуществующие
 * свойства вроде `part.Enabled`, которые Studio выдаст как ошибку в рантайме.
 *
 * Список свойств — из официального API dump Roblox (классы Part, BasePart,
 * Instance, GuiObject, TextLabel, ProximityPrompt, SpawnLocation и т.д.).
 *
 * Запуск: node tools/check-properties.js
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "src");

// Свойства по классам (только те, что реально используются в проекте + частые)
const PROPERTIES = {
  // Общие для всех Instance
  Instance: [
    "Name", "Parent", "Archivable", "ClassName", "Attributes",
  ],
  // BasePart и наследники
  BasePart: [
    "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow", "Color",
    "CFrame", "CustomPhysicalProperties", "Massless", "Material", "MaterialVariant",
    "Orientation", "Position", "Reflectance", "Rotation", "Size", "Transparency",
    "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface",
    "Locked", "CollisionGroup", "CFrame", "PivotOffset", "AssemblyLinearVelocity",
    "AssemblyAngularVelocity", "BrickColor", "Shape", "Velocity", "RootPriority",
  ],
  Part: ["Shape", "FormFactor"],
  MeshPart: ["MeshId", "TextureID"],
  // GUI
  GuiBase2d: ["AbsolutePosition", "AbsoluteSize", "AbsoluteRotation", "SelectionImageObject"],
  GuiObject: [
    "Active", "AnchorPoint", "AutomaticSize", "BackgroundColor3", "BackgroundTransparency",
    "BorderColor3", "BorderMode", "BorderSizePixel", "ClipsDescendants", "Draggable",
    "Interactable", "LayoutOrder", "NextSelectionDown", "NextSelectionLeft",
    "NextSelectionRight", "NextSelectionUp", "Position", "Rotation", "Selectable",
    "SelectionOrder", "Size", "SizeConstraint", "Visible", "ZIndex",
  ],
  GuiButton: ["AutoButtonColor", "Modal", "Selected", "Style"],
  TextButton: ["AutoButtonColor", "Modal", "Selected", "Style", "Text"],
  TextLabel: [
    "Font", "FontFace", "LineHeight", "MaxVisibleGraphemes", "RichText",
    "Text", "TextColor3", "TextDirection", "TextScaled", "TextSize",
    "TextStrokeColor3", "TextStrokeTransparency", "TextTransparency",
    "TextTruncate", "TextWrapped", "TextXAlignment", "TextYAlignment",
    "TextFits", "TextBounds",
  ],
  TextButton_Text: ["Font", "Text", "TextColor3", "TextSize", "TextWrapped", "TextXAlignment", "TextYAlignment", "TextScaled", "TextTruncate"],
  Frame: ["Style"],
  ScrollingFrame: [
    "AbsoluteCanvasSize", "AbsoluteWindowSize", "AutomaticCanvasSize", "CanvasPosition",
    "CanvasSize", "ElasticBehavior", "HorizontalScrollBarInset", "ScrollBarImageColor3",
    "ScrollBarImageTransparency", "ScrollBarThickness", "ScrollingDirection",
    "ScrollingEnabled", "VerticalScrollBarInset", "VerticalScrollBarPosition",
    "ScrollBarImageTransparency",
  ],
  // UI модификаторы
  UICorner: ["CornerRadius"],
  UIStroke: ["Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode"],
  UIPadding: ["PaddingBottom", "PaddingLeft", "PaddingRight", "PaddingTop"],
  UIListLayout: [
    "FillDirection", "HorizontalAlignment", "HorizontalFlex", "ItemLineAlignment",
    "Padding", "SortOrder", "VerticalAlignment", "VerticalFlex", "Wraps",
  ],
  UIGridLayout: ["CellPadding", "CellSize", "FillDirection", "FillDirectionMaxCells", "HorizontalAlignment", "SortOrder", "StartCorner", "VerticalAlignment"],
  UIGradient: ["Color", "Enabled", "Offset", "Rotation", "Transparency"],
  UIScale: ["Scale"],
  UIAspectRatioConstraint: ["AspectRatio", "AspectType", "DominantAxis"],
  UISizeConstraint: ["MaxSize", "MinSize"],
  UIScaleConstraint: ["MaxSize", "MinSize"],
  // Прочее
  BillboardGui: [
    "Adornee", "AlwaysOnTop", "Brightness", "ClipsDescendants", "Enabled", "ExtentsOffset",
    "ExtentsOffsetWorldSpace", "LightInfluence", "MaxDistance", "PlayerToHideFrom",
    "Size", "SizeOffset", "StudsOffset", "StudsOffsetWorldSpace",
  ],
  SurfaceGui: [
    "Adornee", "AlwaysOnTop", "Brightness", "CanvasSize", "ClipsDescendants", "Enabled",
    "Face", "LightInfluence", "MaxDistance", "PixelsPerStud", "SizingMode", "ToolPunchThroughDistance", "ZOffset",
  ],
  Highlight: ["Adornee", "DepthMode", "Enabled", "FillColor", "FillTransparency", "OutlineColor", "OutlineTransparency"],
  PointLight: ["Brightness", "Color", "Enabled", "Range", "Shadows", "Name", "Parent"],
  SpecialMesh: ["MeshId", "MeshType", "Offset", "Scale", "VertexColor", "TextureId"],
  SpawnLocation: [
    "AllowTeamChangeOnTouch", "Duration", "Enabled", "Neutral", "TeamColor", "Color",
    "Anchored", "CanCollide", "Transparency", "Material", "Size", "Position", "Name", "Parent",
    "TopSurface", "BottomSurface",
  ],
  ProximityPrompt: [
    "ActionText", "ClickablePrompt", "Enabled", "Exclusivity", "GamepadKeyCode",
    "HoldDuration", "KeyboardKeyCode", "MaxActivationDistance", "ObjectText",
    "RequiresLineOfSight", "Style", "UIOffset",
  ],
  Folder: ["Name", "Parent", "Archivable"],
  Model: ["Name", "Parent", "PrimaryPart", "WorldPivot", "Archivable"],
  RemoteEvent: ["Name", "Parent"],
  RemoteFunction: ["Name", "Parent"],
  Atmosphere: ["Color", "Decay", "Density", "Glare", "Haze", "Offset"],
  Humanoid: [
    "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "Health", "MaxHealth",
    "DisplayName", "DisplayDistanceType", "HipHeight", "NameDisplayDistance",
    "HealthDisplayDistance", "AutoRotate", "CameraOffset", "MoveDirection",
  ],
  Player: ["DisplayName", "Name", "UserId", "Character", "Team", "TeamColor", "CameraMaxZoomDistance"],
  Camera: ["ViewportSize", "CameraType", "CFrame", "FieldOfView"],
  ScreenGui: [
    "DisplayOrder", "Enabled", "IgnoreGuiInset", "ResetOnSpawn", "ScreenInsets",
    "ClipToDeviceSafeArea", "SafeAreaCompatibility", "ZIndexBehavior",
  ],
  RemoteFunction: ["Name", "Parent", "OnServerInvoke", "OnClientInvoke"],
  Lighting_props: [
    "Ambient", "Brightness", "ClockTime", "ColorShift_Bottom", "ColorShift_Top",
    "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation",
    "FogColor", "FogEnd", "FogStart", "GeographicLatitude", "GlobalShadows",
    "OutdoorAmbient", "ShadowSoftness", "TimeOfDay", "Technology",
  ],
};

const KNOWN = new Set();
for (const list of Object.values(PROPERTIES)) {
  for (const p of list) KNOWN.add(p);
}

// Свойства, которые есть у большинства Instance (и потому безопасны)
const UNIVERSAL = new Set([
  "Name", "Parent", "Archivable", "ClassName", "Destroy", "Clone", "GetChildren",
  "FindFirstChild", "WaitForChild", "IsA", "GetAttribute", "SetAttribute",
  "ChildAdded", "ChildRemoved", "AncestryChanged", "Destroying", "Changed",
]);

// Свойства RemoteFunction/RemoteEvent, назначаемые через промежуточную таблицу
const EXTRA_OK = new Set(["OnServerInvoke", "OnClientInvoke", "OnServerEvent", "OnClientEvent"]);

// Имена переменных с нашими собственными Lua-таблицам (не Instance)
const OWN_TABLES = new Set([
  "data", "carried", "cooldown", "base", "state", "entry", "entries", "info",
  "payload", "eggType", "upgradeConfig", "Config", "raw", "result", "snapshot",
  "cachedEntries", "cachedCoins", "Map", "Data", "Core", "self", "ctx",
  "remotes", "mapData", "baseState", "playerData", "groundEgg", "victimCarried",
  "thief", "victim", "canvas", "props", "colors", "types", "options",
]);

// Часто встречающиеся свойства/методы, которые мы просто игнорируем
const IGNORE = new Set([
  "X", "Y", "Z", "Magnitude", "Unit", "p", "x", "y", "z", "id", "w", "h", "r", "g", "b",
]);

function collectLuaFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectLuaFiles(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

let issues = 0;

for (const file of collectLuaFiles(ROOT).sort()) {
  const src = fs.readFileSync(file, "utf8");
  const lines = src.split("\n");
  const relative = path.relative(path.join(__dirname, ".."), file);

  lines.forEach((line, index) => {
    // ищем присваивания вида  object.Property = ...
    const assignRe = /([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/g;
    let match;
    while ((match = assignRe.exec(line)) !== null) {
      const [, obj, prop] = match;

      // пропускаем очевидно не-Roblox объекты
      if (["math", "string", "table", "os", "workspace", "game", "script"].includes(obj)) continue;
      if (OWN_TABLES.has(obj)) continue;
      if (IGNORE.has(prop)) continue;
      if (KNOWN.has(prop) || UNIVERSAL.has(prop) || EXTRA_OK.has(prop)) continue;

      // комментарии пропускаем
      const commentIndex = line.indexOf("--");
      if (commentIndex !== -1 && commentIndex < match.index) continue;
      // строковые литералы — грубая проверка
      const before = line.slice(0, match.index);
      if ((before.match(/"/g) || []).length % 2 !== 0) continue;

      issues++;
      console.log(`  ⚠️  ${relative}:${index + 1}`);
      console.log(`      ${obj}.${prop} — свойство не найдено в списке API Roblox`);
      console.log(`      ${line.trim().slice(0, 120)}`);
    }
  });
}

console.log("");

if (issues === 0) {
  console.log("✅ Все использованные свойства Roblox найдены в API.");
  process.exit(0);
} else {
  console.log(`Найдено подозрительных мест: ${issues}`);
  console.log("Проверь их вручную — возможно, это опечатка.");
  process.exit(1);
}
