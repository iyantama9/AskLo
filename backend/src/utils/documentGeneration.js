const PDFDocument = require('pdfkit');
const { Document, Paragraph, TextRun, HeadingLevel, AlignmentType } = require('docx');

/**
 * Generate PDF buffer from markdown-like text
 * @param {string} content - Text content to convert
 * @param {string} title - Document title
 * @returns {Promise<Buffer>} PDF buffer
 */
async function generatePDF(content, title = 'Document') {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        margins: { top: 50, bottom: 50, left: 50, right: 50 },
        size: 'A4',
      });

      const chunks = [];
      doc.on('data', (chunk) => chunks.push(chunk));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      // Add title
      doc.fontSize(18).font('Helvetica-Bold').text(title, { align: 'center' });
      doc.moveDown(1.5);

      // Process content line by line
      const lines = content.split('\n');
      for (const line of lines) {
        const trimmed = line.trim();

        if (!trimmed) {
          doc.moveDown(0.5);
          continue;
        }

        // Headers
        if (trimmed.startsWith('# ')) {
          doc.fontSize(16).font('Helvetica-Bold').text(trimmed.slice(2));
          doc.moveDown(0.8);
        } else if (trimmed.startsWith('## ')) {
          doc.fontSize(14).font('Helvetica-Bold').text(trimmed.slice(3));
          doc.moveDown(0.6);
        } else if (trimmed.startsWith('### ')) {
          doc.fontSize(12).font('Helvetica-Bold').text(trimmed.slice(4));
          doc.moveDown(0.5);
        }
        // Lists
        else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
          doc.fontSize(11).font('Helvetica').text(`  • ${trimmed.slice(2)}`);
          doc.moveDown(0.3);
        }
        // Numbered lists
        else if (/^\d+\.\s/.test(trimmed)) {
          doc.fontSize(11).font('Helvetica').text(`  ${trimmed}`);
          doc.moveDown(0.3);
        }
        // Regular text
        else {
          doc.fontSize(11).font('Helvetica').text(trimmed, { align: 'left' });
          doc.moveDown(0.4);
        }
      }

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

/**
 * Generate DOCX buffer from markdown-like text
 * @param {string} content - Text content to convert
 * @param {string} title - Document title
 * @returns {Promise<Buffer>} DOCX buffer
 */
async function generateDOCX(content, title = 'Document') {
  const { Packer } = require('docx');

  const children = [];

  // Add title
  children.push(
    new Paragraph({
      text: title,
      heading: HeadingLevel.TITLE,
      alignment: AlignmentType.CENTER,
      spacing: { after: 400 },
    })
  );

  // Process content line by line
  const lines = content.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();

    if (!trimmed) {
      children.push(new Paragraph({ text: '' }));
      continue;
    }

    // Headers
    if (trimmed.startsWith('# ')) {
      children.push(
        new Paragraph({
          text: trimmed.slice(2),
          heading: HeadingLevel.HEADING_1,
          spacing: { before: 240, after: 120 },
        })
      );
    } else if (trimmed.startsWith('## ')) {
      children.push(
        new Paragraph({
          text: trimmed.slice(3),
          heading: HeadingLevel.HEADING_2,
          spacing: { before: 200, after: 100 },
        })
      );
    } else if (trimmed.startsWith('### ')) {
      children.push(
        new Paragraph({
          text: trimmed.slice(4),
          heading: HeadingLevel.HEADING_3,
          spacing: { before: 160, after: 80 },
        })
      );
    }
    // Lists
    else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      children.push(
        new Paragraph({
          text: trimmed.slice(2),
          bullet: { level: 0 },
          spacing: { after: 100 },
        })
      );
    }
    // Numbered lists
    else if (/^\d+\.\s/.test(trimmed)) {
      const text = trimmed.replace(/^\d+\.\s/, '');
      children.push(
        new Paragraph({
          text,
          numbering: { reference: 'default-numbering', level: 0 },
          spacing: { after: 100 },
        })
      );
    }
    // Bold text
    else if (/\*\*(.+?)\*\*/.test(trimmed)) {
      const parts = trimmed.split(/(\*\*.+?\*\*)/);
      const runs = parts.map((part) => {
        if (part.startsWith('**') && part.endsWith('**')) {
          return new TextRun({ text: part.slice(2, -2), bold: true });
        }
        return new TextRun({ text: part });
      });
      children.push(new Paragraph({ children: runs, spacing: { after: 120 } }));
    }
    // Regular text
    else {
      children.push(
        new Paragraph({
          text: trimmed,
          spacing: { after: 120 },
        })
      );
    }
  }

  const doc = new Document({
    numbering: {
      config: [
        {
          reference: 'default-numbering',
          levels: [
            {
              level: 0,
              format: 'decimal',
              text: '%1.',
              alignment: AlignmentType.LEFT,
            },
          ],
        },
      ],
    },
    sections: [
      {
        properties: {},
        children,
      },
    ],
  });

  return await Packer.toBuffer(doc);
}

/**
 * Generate CSV from structured data
 * @param {string} content - CSV content (already formatted)
 * @returns {Buffer} CSV buffer
 */
function generateCSV(content) {
  return Buffer.from(content, 'utf8');
}

/**
 * Detect if content looks like CSV
 * @param {string} content
 * @returns {boolean}
 */
function looksLikeCSV(content) {
  const lines = content.trim().split('\n').slice(0, 5);
  if (lines.length < 2) return false;

  const separators = lines.map((line) => (line.match(/,/g) || []).length);
  const avgSep = separators.reduce((a, b) => a + b, 0) / separators.length;

  return avgSep >= 2 && separators.every((count) => Math.abs(count - avgSep) <= 1);
}

module.exports = {
  generatePDF,
  generateDOCX,
  generateCSV,
  looksLikeCSV,
};
