import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";
function crc(buffer) {
  let c = 0xffffffff;
  for (const b of buffer) {
    c ^= b;
    for (let i = 0; i < 8; i++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const t = Buffer.from(type),
    n = Buffer.alloc(4),
    c = Buffer.alloc(4);
  n.writeUInt32BE(data.length);
  c.writeUInt32BE(crc(Buffer.concat([t, data])));
  return Buffer.concat([n, t, data, c]);
}
const header = Buffer.alloc(13);
header.writeUInt32BE(8, 0);
header.writeUInt32BE(8, 4);
header[8] = 8;
header[9] = 6;
const rows = [];
for (let y = 0; y < 8; y++) {
  const row = [0];
  for (let x = 0; x < 8; x++)
    row.push(...(x < 4 === y < 4 ? [37, 80, 94, 255] : [26, 53, 67, 255]));
  rows.push(Buffer.from(row));
}
writeFileSync(
  new URL("../ui/styles/theme/checker.png", import.meta.url),
  Buffer.concat([
    Buffer.from("89504e470d0a1a0a", "hex"),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.concat(rows))),
    chunk("IEND", Buffer.alloc(0)),
  ]),
);
