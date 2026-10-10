import { createHash } from "node:crypto";
import { fail, validateEntity, decorate } from "./domain.mjs";

// CSV records can contain commas, escaped quotes and physical newlines.
export function parseCSV(text) {
  if (typeof text !== "string" || Buffer.byteLength(text) > 7000000)
    fail("Choose a Nara CSV smaller than 7 MB");
  text = text.replace(/^\uFEFF/, "");
  const rows = [];
  let row = [],
    cell = "",
    quoted = false,
    closed = false;
  const cellEnd = () => {
    row.push(cell);
    cell = "";
    closed = false;
  };
  const rowEnd = () => {
    cellEnd();
    if (row.some((x) => x !== "")) rows.push(row);
    row = [];
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else cell += c;
      continue;
    }
    if (c === '"') {
      if (cell || closed)
        fail(`Invalid CSV quoting near record ${rows.length + 1}`);
      quoted = true;
    } else if (c === ",") cellEnd();
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      rowEnd();
    } else {
      if (closed)
        fail(
          `Unexpected text after a CSV quote near record ${rows.length + 1}`,
        );
      cell += c;
    }
  }
  if (quoted)
    fail("The CSV ends inside a quoted value. Export the file again.");
  if (cell || row.length || closed) rowEnd();
  if (rows.length < 2) fail("The CSV has no records");
  return rows;
}
const stable = (...parts) =>
  "nara-" +
  createHash("sha256").update(JSON.stringify(parts)).digest("hex").slice(0, 40);
function localDate(value, zone) {
  const m = /^(\d{4})-(\d\d)-(\d\d)(?:[ T](\d\d):(\d\d):(\d\d))?$/.exec(
    value ?? "",
  );
  if (!m) return NaN;
  const parts = m.slice(1).map((x) => Number(x ?? 0));
  if (
    parts[1] < 1 ||
    parts[1] > 12 ||
    parts[2] < 1 ||
    parts[2] > 31 ||
    parts[3] > 23 ||
    parts[4] > 59 ||
    parts[5] > 59
  )
    return NaN;
  const desired = Date.UTC(parts[0], parts[1] - 1, ...parts.slice(2));
  if (new Date(desired).toISOString().slice(0, 10) !== value.slice(0, 10))
    return NaN;
  const format = new Intl.DateTimeFormat("en-US", {
    timeZone: zone || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  let result = desired;
  for (let i = 0; i < 3; i++) {
    const p = Object.fromEntries(
      format.formatToParts(new Date(result)).map((x) => [x.type, x.value]),
    );
    result +=
      desired -
      Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  }
  return result / 1000;
}
const volumeUnit = (v) => ({ FLOZ: "oz", ML: "mL" })[v] ?? v;
const growthUnit = (v) =>
  ({ LB: "lb", OZ: "oz", KG: "kg", IN: "in", CM: "cm" })[v] ?? v;
const titleCase = (v = "") =>
  v
    .split(" ")
    .filter(Boolean)
    .map((x) => x[0].toUpperCase() + x.slice(1).toLowerCase())
    .join(" ");
export function planNara(
  csv,
  { familyID, existing = [], targetChildID = "" } = {},
) {
  if (typeof familyID !== "string" || !familyID)
    fail("Choose a family before importing");
  if (
    targetChildID &&
    !existing.some(
      (e) => e.id === targetChildID && e.type === "child" && !e.deleted,
    )
  )
    fail("Choose a child in this family");
  const [headers, ...rows] = parseCSV(csv);
  for (const key of [
    "Type",
    "Profile Name",
    "Time Zone",
    "_profileKey",
    "_activityKey",
  ])
    if (!headers.includes(key)) fail(`Missing Nara column: ${key}`);
  if (new Set(headers).size !== headers.length)
    fail("The CSV has duplicate columns");
  const entities = [],
    issues = [],
    counts = {},
    seen = new Set(existing.map((e) => e.id));
  let duplicates = 0,
    skipped = 0;
  const profileKeys = new Set(
    rows.map((r) => r[headers.indexOf("_profileKey")]).filter(Boolean),
  );
  if (targetChildID && profileKeys.size !== 1)
    fail("Import multiple profiles as new children");
  const profiles = new Map();
  const rawRows = rows.map((cells, i) => {
    if (
      cells.length !== headers.length &&
      !(
        cells[0] === "Profile" &&
        cells.length === headers.length - 1 &&
        headers.at(-1) === "_activityKey"
      )
    )
      fail(
        `Record ${i + 2} has ${cells.length} columns; expected ${headers.length}`,
      );
    return Object.fromEntries(headers.map((h, j) => [h, cells[j] ?? ""]));
  });
  for (const r of rawRows) {
    const key = r._profileKey;
    if (!key) continue;
    const profile = profiles.get(key) ?? {
      name: r["Profile Name"],
      zone: r["Time Zone"],
      raw: r,
    };
    if (r.Type === "Profile") profile.raw = r;
    profiles.set(key, profile);
  }
  const childIDs = new Map();
  const add = (
    r,
    part,
    type,
    title,
    at,
    fields = {},
    end = null,
    rowNumber,
  ) => {
    const id = stable(
      familyID,
      r._profileKey,
      r.Type === "Profile" ? "profile" : r._activityKey,
      part,
    );
    if (seen.has(id)) {
      duplicates++;
      return;
    }
    seen.add(id);
    const imported = {
      source: "Nara Baby",
      profileKey: r._profileKey,
      activityKey: r._activityKey,
      part,
      createdBy: r["Created By Caregiver"] ?? "",
      updatedBy: r["Last Updated By Caregiver"] ?? "",
      timeZone: r["Time Zone"],
      raw: r,
    };
    const input = {
      id,
      type,
      childID: type === "child" ? "" : childIDs.get(r._profileKey),
      title: title || type,
      at,
      end,
      fields,
    };
    try {
      const e = validateEntity(input, { imported: true });
      e.imported = imported;
      e.actor = imported.createdBy;
      e.version = 1;
      e.updatedAt = 0;
      entities.push(e);
      counts[type] = (counts[type] ?? 0) + 1;
    } catch (error) {
      skipped++;
      issues.push({ row: rowNumber, message: error.message });
    }
  };
  for (const [key, p] of profiles) {
    const importedTargets = new Set(
      existing
        .filter(
          (e) =>
            e.imported?.source === "Nara Baby" && e.imported.profileKey === key,
        )
        .map((e) => (e.type === "child" ? e.id : e.childID))
        .filter(Boolean),
    );
    if (importedTargets.size > 1)
      fail(
        "This source profile is linked to multiple children. Check its imported records.",
      );
    const previousTarget = [...importedTargets][0];
    if (targetChildID && previousTarget && targetChildID !== previousTarget)
      fail("This source profile was already imported into another child.");
    const id =
      targetChildID ||
      previousTarget ||
      stable(familyID, key, "profile", "child");
    childIDs.set(key, id);
    if (
      (targetChildID || previousTarget) &&
      existing.some((e) => e.id === id && e.type === "child" && !e.deleted)
    ) {
      if (existing.some((e) => e.id === id && e.imported?.profileKey === key))
        duplicates++;
      continue;
    }
    const r = p.raw;
    let at;
    try {
      at = localDate(r["[Profile] Birth Date"], p.zone);
    } catch {}
    if (!Number.isFinite(at)) {
      at = 0;
      issues.push({
        row: 0,
        message:
          "A profile has no valid birthday. Its source values are retained.",
      });
    }
    add({ ...r, Type: "Profile" }, "child", "child", p.name, at, {}, null, 0);
  }
  for (let i = 0; i < rawRows.length; i++) {
    const r = rawRows[i],
      rowNumber = i + 2;
    if (r.Type === "Profile") continue;
    if (!r._profileKey || !r._activityKey) {
      skipped++;
      issues.push({
        row: rowNumber,
        message: "Missing source profile or activity ID",
      });
      continue;
    }
    let at;
    try {
      at = r["Start Date/time (Epoch)"]
        ? Number(r["Start Date/time (Epoch)"]) / 1000
        : localDate(r["Start Date/time"], r["Time Zone"]);
    } catch {}
    if (!Number.isFinite(at)) {
      skipped++;
      issues.push({ row: rowNumber, message: "Invalid start date" });
      continue;
    }
    const notes = r.Note ? { notes: r.Note } : {};
    const emit = (part, type, title, fields = {}, end = null) =>
      add(r, part, type, title, at, { ...fields, ...notes }, end, rowNumber);
    switch (r.Type) {
      case "Bottle Feed": {
        const milk = r["[Bottle Feed] Breast Milk Volume"],
          formula = r["[Bottle Feed] Formula Volume"],
          generic = r["[Bottle Feed] Volume"];
        let amount = generic,
          unit = volumeUnit(r["[Bottle Feed] Volume Unit"]);
        if (!amount) {
          if (milk && formula) {
            const mu = volumeUnit(r["[Bottle Feed] Breast Milk Volume Unit"]),
              fu = volumeUnit(r["[Bottle Feed] Formula Volume Unit"]);
            if (["oz", "mL"].includes(mu) && ["oz", "mL"].includes(fu)) {
              amount = String(
                Number(milk) * (mu === "oz" ? 29.5735295625 : 1) +
                  Number(formula) * (fu === "oz" ? 29.5735295625 : 1),
              );
              unit = "mL";
            }
          } else {
            amount = formula || milk;
            unit = volumeUnit(
              r[
                formula
                  ? "[Bottle Feed] Formula Volume Unit"
                  : "[Bottle Feed] Breast Milk Volume Unit"
              ],
            );
          }
        }
        if (!amount || !["oz", "mL"].includes(unit)) {
          amount = "";
          unit = "";
          issues.push({
            row: rowNumber,
            message:
              "Bottle amount or unit not recorded; original values retained",
          });
        }
        emit("bottle", "feeding", "Bottle", {
          ...(amount ? { amount, unit } : {}),
          brand: r["[Bottle Feed] Formula Name"] ?? "",
        });
        break;
      }
      case "Diaper":
        emit("diaper", "diaper", "Diaper", {
          contents:
            r["[Diaper] Type"] === "Dirty Wet" ? "Both" : r["[Diaper] Type"],
          detail: r["[Diaper] Detail"] ?? "",
          color: titleCase(r["[Diaper] Dirty Color"]),
          consistency: (r["[Diaper] Dirty Texture"] ?? "")
            .split(" ")
            .filter(Boolean)
            .map(
              (x) =>
                ({
                  MUSH: "Mushy",
                  RUN: "Runny",
                  MUCOUS: "Mucous",
                  SOLID: "Solid",
                })[x] ?? titleCase(x),
            )
            .join(" "),
        });
        break;
      case "Sleep": {
        let end;
        try {
          end = r["[Sleep] End Date/time (Epoch)"]
            ? Number(r["[Sleep] End Date/time (Epoch)"]) / 1000
            : r["[Sleep] End Date/time"]
              ? localDate(r["[Sleep] End Date/time"], r["Time Zone"])
              : r["[Sleep] Duration (Seconds)"] !== ""
                ? at + Number(r["[Sleep] Duration (Seconds)"])
                : NaN;
        } catch {}
        if (!Number.isFinite(end)) {
          skipped++;
          issues.push({
            row: rowNumber,
            message: "Sleep has no valid end; not imported as a running timer",
          });
          break;
        }
        emit("sleep", "sleep", "Sleep", {}, end);
        break;
      }
      case "Growth": {
        let measurements = 0;
        for (const [key, measure] of [
          ["Head Size", "Head circumference"],
          ["Height", "Height"],
          ["Weight", "Weight"],
        ]) {
          if (!r[`[Growth] ${key}`]) continue;
          measurements++;
          const unit = growthUnit(r[`[Growth] ${key} Unit`]) ?? "";
          emit(key, "growth", "Measurement", {
            measure,
            value: r[`[Growth] ${key}`],
            unit,
          });
          if (!unit)
            issues.push({
              row: rowNumber,
              message: "Measurement unit unknown; original values retained",
            });
        }
        if (!measurements) {
          emit("growth-note", "note", "Growth record");
          issues.push({
            row: rowNumber,
            message: "No measurement recorded; source row retained as a note",
          });
        }
        break;
      }
      case "Vaccine": {
        const names = (r["[Vaccine] Vaccine"] ?? "")
          .split(/\r?\n/)
          .filter(Boolean);
        names.forEach((name, i) => emit("vaccine-" + i, "vaccine", name));
        if (!names.length) {
          emit("vaccine-note", "note", "Vaccine record");
          issues.push({
            row: rowNumber,
            message: "Vaccine name unknown; source row retained as a note",
          });
        }
        break;
      }
      case "Routine":
        emit("routine", "note", r["[Routine] Routine"] || "Routine");
        break;
      case "Medical": {
        const medicine = r["[Medical] Medication"];
        if (medicine) {
          const m = /^(.+?),\s*([\d.]+)(?:\s*\(([^)]+)\))?$/.exec(medicine);
          emit(
            "medication",
            "medication",
            m ? m[1] : medicine,
            m
              ? {
                  dose: m[2],
                  ...(m[3]
                    ? { unit: m[3].toUpperCase() === "ML" ? "mL" : m[3] }
                    : {}),
                }
              : {},
          );
          if (!m?.[3])
            issues.push({
              row: rowNumber,
              message:
                "Medication dose or unit unknown; original text retained",
            });
        }
        if (r["[Medical] Temperature"])
          emit("temperature", "temperature", "Temperature", {
            value: r["[Medical] Temperature"],
            unit:
              { F: "°F", C: "°C", FAHRENHEIT: "°F", CELSIUS: "°C" }[
                r["[Medical] Temperature Unit"]
              ] ??
              r["[Medical] Temperature Unit"] ??
              "",
          });
        if (!medicine && !r["[Medical] Temperature"])
          emit("medical", "note", "Medical note");
        break;
      }
      default:
        emit("other", "note", r.Type || "Nara record");
        issues.push({
          row: rowNumber,
          message: "Activity retained as a note with original source fields",
        });
    }
  }
  const all = [...existing, ...entities];
  if (
    entities.some(
      (e) =>
        e.type !== "child" &&
        !all.some(
          (child) =>
            child.type === "child" && child.id === e.childID && !child.deleted,
        ),
    )
  )
    fail(
      "The source child was removed. Imported history will not recreate deleted records.",
    );
  return {
    sourceRows: rows.length,
    records: entities.map((e) => decorate(e, all)),
    counts,
    duplicates,
    skipped,
    issues,
    profiles: [...profiles].map(([key, p]) => ({
      key,
      name: p.name,
      childID: childIDs.get(key),
    })),
  };
}
