import fs from "node:fs";

const [archivePath, ...rawOffsets] = process.argv.slice(2);

if (!archivePath || rawOffsets.length === 0) {
  console.error("usage: node inspect-asar.mjs <archive> <absolute-offset> [...]");
  process.exit(2);
}

const archive = fs.openSync(archivePath, "r");
const prefix = Buffer.alloc(16);
fs.readSync(archive, prefix, 0, prefix.length, 0);

const headerPayloadSize = prefix.readUInt32LE(4);
const headerJSONSize = prefix.readUInt32LE(12);
const headerBuffer = Buffer.alloc(headerJSONSize);
fs.readSync(archive, headerBuffer, 0, headerJSONSize, 16);
const header = JSON.parse(headerBuffer.toString("utf8"));
const contentStart = 8 + headerPayloadSize;

const entries = [];

function visit(files, parentPath = "") {
  for (const [name, entry] of Object.entries(files)) {
    const entryPath = parentPath ? `${parentPath}/${name}` : name;
    if (entry.files) {
      visit(entry.files, entryPath);
      continue;
    }

    if (entry.offset === undefined || entry.size === undefined) {
      continue;
    }

    const start = contentStart + Number(entry.offset);
    entries.push({
      path: entryPath,
      start,
      end: start + Number(entry.size),
      size: Number(entry.size),
    });
  }
}

visit(header.files);

for (const rawOffset of rawOffsets) {
  const absoluteOffset = Number(rawOffset);
  const entry = entries.find(
    (candidate) =>
      absoluteOffset >= candidate.start && absoluteOffset < candidate.end,
  );

  if (!entry) {
    console.log(
      JSON.stringify({ absoluteOffset, error: "no packed entry contains offset" }),
    );
    continue;
  }

  const contextRadius = 1_500;
  const contextStart = Math.max(entry.start, absoluteOffset - contextRadius);
  const contextEnd = Math.min(entry.end, absoluteOffset + contextRadius);
  const context = Buffer.alloc(contextEnd - contextStart);
  fs.readSync(archive, context, 0, context.length, contextStart);

  console.log(
    JSON.stringify(
      {
        absoluteOffset,
        archiveEntry: entry,
        context: context
          .toString("utf8")
          .replaceAll("\u0000", "")
          .replace(/\s+/g, " "),
      },
      null,
      2,
    ),
  );
}

fs.closeSync(archive);
