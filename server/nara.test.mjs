import test from "node:test";
import assert from "node:assert/strict";
import { planNara, parseCSV } from "./nara.mjs";
import { Store } from "./store.mjs";
import { summary } from "./domain.mjs";
import { readFileSync } from "node:fs";
const csv = readFileSync(
  new URL("../contracts/nara-sample.csv", import.meta.url),
  "utf8",
);
test("Nara mapping preserves multiline values, unknowns, precision and multiple records", () => {
  const r = planNara(csv, { familyID: "family" });
  assert.equal(r.sourceRows, 9);
  assert.equal(r.records.length, 11);
  assert.equal(r.skipped, 0);
  const feeds = r.records.filter((e) => e.type === "feeding");
  assert.equal(feeds[0].fields.amount, "5");
  assert.equal(feeds[0].fields.unit, "oz");
  assert.equal(feeds[0].fields.notes, 'a comma, a "quote"\nand emoji 😂');
  assert.equal(feeds[1].fields.amount, undefined);
  const sleep = r.records.filter((e) => e.type === "sleep");
  assert.equal(sleep[0].end, 1791588650.178);
  assert.equal(sleep[1].end, sleep[1].at);
  const diaper = r.records.find((e) => e.type === "diaper");
  assert.equal(diaper.fields.contents, "Both");
  assert.equal(diaper.fields.color, "Brown Yellow");
  assert.equal(diaper.fields.consistency, "Mucous Mushy");
  const medicine = r.records.find((e) => e.type === "medication");
  assert.equal(medicine.fields.unit, undefined);
  assert.equal(medicine.imported.updatedBy, "Editor");
  assert.equal(medicine.actor, "Writer");
  assert.equal(summary(r.records, feeds[0].childID, 1791589500).feedingML, 148);
});
test("CSV rejects incomplete quotes and wrong column counts instead of shifting values", () => {
  assert.throws(() => parseCSV('Type\n"broken'), /quoted/);
  assert.throws(
    () => planNara(csv + '\n"extra"', { familyID: "f" }),
    /columns/,
  );
  assert.throws(() => parseCSV('a\n"b"garbage'), /after/);
});
test("Import is atomic, family scoped, idempotent and does not overwrite edited history or notify", () => {
  const store = new Store();
  try {
    const a = store.account("a", "User"),
      b = store.account("b", "User");
    const first = store.importNara(a, {
      csv,
      familyID: a.family,
      commit: true,
    });
    assert.equal(first.snapshot.entities.length, 11);
    assert.equal(first.snapshot.members.length, 1);
    const feed = first.snapshot.entities.find((e) => e.type === "feeding");
    store.put(a.family, { ...feed, title: "Edited" });
    const again = store.importNara(a, {
      csv,
      familyID: a.family,
      commit: true,
    });
    assert.equal(again.duplicates, 11);
    assert.equal(again.records, undefined);
    assert.equal(
      store.list(a.family).find((e) => e.id === feed.id).title,
      "Edited",
    );
    assert.equal(store.db.prepare("SELECT count(*) n FROM jobs").get().n, 0);
    const other = store.importNara(b, {
      csv,
      familyID: b.family,
      commit: true,
    });
    assert.equal(other.duplicates, 0);
    assert.ok(!other.snapshot.entities.some((e) => e.id === feed.id));
    assert.throws(
      () => store.importNara(a, { csv, familyID: b.family, commit: true }),
      /family changed/,
    );
  } finally {
    store.close();
  }
});
test("Existing child mapping avoids a second child and rejects cross-family mapping", () => {
  const s = new Store();
  try {
    const u = s.account("u");
    s.put(u.family, {
      id: "existing-child",
      type: "child",
      childID: "",
      title: "Existing",
      at: 0,
      fields: {},
      deleted: false,
      version: 1,
    });
    const report = s.importNara(u, {
      csv,
      familyID: u.family,
      targetChildID: "existing-child",
      commit: true,
    });
    assert.equal(report.counts.child, undefined);
    const repeat = s.importNara(u, { csv, familyID: u.family, commit: true });
    assert.equal(repeat.counts.child, undefined);
    assert.equal(s.list(u.family).filter((e) => e.type === "child").length, 1);
    assert.ok(
      s
        .list(u.family)
        .filter((e) => e.type !== "child")
        .every((e) => e.childID === "existing-child"),
    );
    assert.throws(
      () =>
        s.importNara(u, { csv, familyID: u.family, targetChildID: "foreign" }),
      /this family/,
    );
  } finally {
    s.close();
  }
});

test("Missing diaper color remains empty rather than a literal undefined value", () => {
  const emptyColor = csv.replace("BROWN YELLOW", "");
  const diaper = planNara(emptyColor, {
    familyID: "synthetic-family",
  }).records.find((e) => e.type === "diaper");
  assert.equal(diaper.fields.color, "");
  assert.ok(!diaper.detail.includes("undefined"));
});
test("Generic and mixed milk bottle columns preserve original units and compute one amount", () => {
  const header = [
    "Type",
    "Profile Name",
    "Time Zone",
    "_profileKey",
    "_activityKey",
    "Start Date/time (Epoch)",
    "[Bottle Feed] Volume",
    "[Bottle Feed] Volume Unit",
    "[Bottle Feed] Breast Milk Volume",
    "[Bottle Feed] Breast Milk Volume Unit",
    "[Bottle Feed] Formula Volume",
    "[Bottle Feed] Formula Volume Unit",
  ];
  const rows = [
    header,
    [
      "Bottle Feed",
      "Sample child",
      "America/New_York",
      "synthetic-profile",
      "generic",
      "1791588649000",
      "2",
      "FLOZ",
      "",
      "",
      "",
      "",
    ],
    [
      "Bottle Feed",
      "Sample child",
      "America/New_York",
      "synthetic-profile",
      "mixed",
      "1791588649000",
      "",
      "",
      "1",
      "FLOZ",
      "20",
      "ML",
    ],
  ];
  const csv = rows
    .map((row) => row.map((v) => JSON.stringify(v)).join(","))
    .join("\n");
  const feeds = planNara(csv, { familyID: "synthetic-family" }).records.filter(
    (e) => e.type === "feeding",
  );
  assert.equal(feeds[0].fields.amount, "2");
  assert.equal(feeds[0].fields.unit, "oz");
  assert.equal(Number(feeds[1].fields.amount), 49.5735295625);
  assert.equal(feeds[1].fields.unit, "mL");
  assert.equal(
    feeds[1].imported.raw["[Bottle Feed] Breast Milk Volume Unit"],
    "FLOZ",
  );
});

test("Empty growth and vaccine values keep their source row as a note", () => {
  const source = csv
    .replace('"One\nTwo"', '""')
    .replace('"23.5","IN","12.125","LB"', '"","IN","","LB"');
  const report = planNara(source, { familyID: "synthetic-family" });
  assert.ok(
    report.records.some(
      (e) => e.title === "Vaccine record" && e.imported.raw.Type === "Vaccine",
    ),
  );
  assert.ok(
    report.records.some(
      (e) => e.title === "Growth record" && e.imported.raw.Type === "Growth",
    ),
  );
});

test("CSV supports CRLF record endings without shifting quoted commas", () => {
  assert.deepEqual(parseCSV('a,b\r\n"c,d","e"\r\n'), [
    ["a", "b"],
    ["c,d", "e"],
  ]);
});
