#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { Store } from "../server/store.mjs";
const [input, output] = process.argv.slice(2);
if (!input || !output)
  throw new Error("Usage: owner-preview.mjs input.csv private-output.json");
const store = new Store();
try {
  const user = store.account("owner-local-sample", "You", true);
  const report = store.importNara(user, {
    csv: readFileSync(input, "utf8"),
    familyID: user.family,
    commit: true,
    timeZone: "America/New_York",
  });
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify(report.snapshot), { mode: 0o600 });
  console.log(
    JSON.stringify({
      sourceRows: report.sourceRows,
      records: report.snapshot.entities.length,
      counts: report.counts,
      skipped: report.skipped,
      warnings: report.issues.length,
    }),
  );
} finally {
  store.close();
}
