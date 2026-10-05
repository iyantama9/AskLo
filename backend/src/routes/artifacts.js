const express = require("express");
const { pool } = require("../db");
const authMiddleware = require("../middleware/auth");
const { sendError } = require("../utils/errors");
const {
  artifactSummary,
  normalizeArtifactPath,
} = require("../utils/artifactExtraction");

const router = express.Router();
router.use(authMiddleware);

const CRC_TABLE = Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit++) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }
  return value >>> 0;
});

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function dosDateTime(date = new Date()) {
  const year = Math.max(1980, date.getFullYear());
  const time =
    (date.getHours() << 11) |
    (date.getMinutes() << 5) |
    Math.floor(date.getSeconds() / 2);
  const day =
    ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  return { time, day };
}

function writeUInt32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value >>> 0, 0);
  return buffer;
}

function writeUInt16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value & 0xffff, 0);
  return buffer;
}

function createZip(files) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;
  const { time, day } = dosDateTime();

  for (const file of files) {
    const name =
      normalizeArtifactPath(file.path) || file.name || "artifact.txt";
    const nameBuffer = Buffer.from(name, "utf8");
    const contentBuffer = Buffer.from(file.content || "", "utf8");
    const checksum = crc32(contentBuffer);

    const localHeader = Buffer.concat([
      writeUInt32(0x04034b50),
      writeUInt16(20),
      writeUInt16(0x0800),
      writeUInt16(0),
      writeUInt16(time),
      writeUInt16(day),
      writeUInt32(checksum),
      writeUInt32(contentBuffer.length),
      writeUInt32(contentBuffer.length),
      writeUInt16(nameBuffer.length),
      writeUInt16(0),
      nameBuffer,
    ]);
    localParts.push(localHeader, contentBuffer);

    const centralHeader = Buffer.concat([
      writeUInt32(0x02014b50),
      writeUInt16(20),
      writeUInt16(20),
      writeUInt16(0x0800),
      writeUInt16(0),
      writeUInt16(time),
      writeUInt16(day),
      writeUInt32(checksum),
      writeUInt32(contentBuffer.length),
      writeUInt32(contentBuffer.length),
      writeUInt16(nameBuffer.length),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt32(0),
      writeUInt32(offset),
      nameBuffer,
    ]);
    centralParts.push(centralHeader);
    offset += localHeader.length + contentBuffer.length;
  }

  const centralDirectory = Buffer.concat(centralParts);
  const end = Buffer.concat([
    writeUInt32(0x06054b50),
    writeUInt16(0),
    writeUInt16(0),
    writeUInt16(files.length),
    writeUInt16(files.length),
    writeUInt32(centralDirectory.length),
    writeUInt32(offset),
    writeUInt16(0),
  ]);

  return Buffer.concat([...localParts, centralDirectory, end]);
}

async function getOwnedArtifact(userId, artifactId) {
  const result = await pool.query(
    `SELECT * FROM artifacts
     WHERE id = $1 AND owner_id = $2`,
    [artifactId, userId],
  );
  return result.rows[0] || null;
}

function getFiles(row) {
  return Array.isArray(row.files) ? row.files : [];
}

function findFile(row, filePath) {
  const requested = normalizeArtifactPath(filePath);
  return (
    getFiles(row).find(
      (file) => normalizeArtifactPath(file.path) === requested,
    ) || null
  );
}

router.get("/chats/:chatId/artifacts", async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT a.* FROM artifacts a
       JOIN chats c ON c.id = a.chat_id
       WHERE a.chat_id = $1 AND a.owner_id = $2 AND c.user_id = $2
       ORDER BY a.created_at DESC`,
      [req.params.chatId, req.userId],
    );
    res.json(result.rows.map(artifactSummary));
  } catch (err) {
    return sendError(res, req, 500, "Failed to load artifacts", err);
  }
});

router.get("/artifacts/:artifactId", async (req, res) => {
  try {
    const artifact = await getOwnedArtifact(req.userId, req.params.artifactId);
    if (!artifact) return sendError(res, req, 404, "Artifact not found");
    res.json({
      ...artifactSummary(artifact),
      owner_id: artifact.owner_id,
      files: getFiles(artifact),
    });
  } catch (err) {
    return sendError(res, req, 500, "Failed to load artifact", err);
  }
});

router.get("/artifacts/:artifactId/files/*", async (req, res) => {
  try {
    const artifact = await getOwnedArtifact(req.userId, req.params.artifactId);
    if (!artifact) return sendError(res, req, 404, "Artifact not found");

    const file = findFile(artifact, req.params[0]);
    if (!file) return sendError(res, req, 404, "Artifact file not found");

    // Binary files (PDF, DOCX) stored in MinIO
    if (file.url && file.is_binary) {
      return res.redirect(file.url);
    }

    // Text files stored in database
    res.set("Content-Type", file.mime_type || "text/plain; charset=utf-8");
    res.set(
      "Content-Disposition",
      `attachment; filename="${encodeURIComponent(file.name || "artifact.txt")}"`,
    );
    res.set("X-Content-Type-Options", "nosniff");
    return res.send(file.content || "");
  } catch (err) {
    return sendError(res, req, 500, "Failed to download artifact file", err);
  }
});

router.get("/artifacts/:artifactId/download.zip", async (req, res) => {
  try {
    const artifact = await getOwnedArtifact(req.userId, req.params.artifactId);
    if (!artifact) return sendError(res, req, 404, "Artifact not found");

    const zip = createZip(getFiles(artifact));
    res.set("Content-Type", "application/zip");
    res.set(
      "Content-Disposition",
      `attachment; filename="${encodeURIComponent(artifact.title || "artifact")}.zip"`,
    );
    res.set("Content-Length", String(zip.length));
    res.set("X-Content-Type-Options", "nosniff");
    return res.send(zip);
  } catch (err) {
    return sendError(res, req, 500, "Failed to download artifact zip", err);
  }
});

module.exports = router;
