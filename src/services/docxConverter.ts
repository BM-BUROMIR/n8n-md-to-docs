import { Document, Paragraph, TextRun, HeadingLevel, Packer, Table, TableRow, TableCell, BorderStyle } from 'docx';
import { marked } from 'marked';
import { logger } from 'firebase-functions/v2';
import type { Tokens } from 'marked';
import { mathJaxReady, convertLatex2Math } from '@hungknguyen/docx-math-converter';

// Initialize MathJax (needs to be called once at startup)
let mathJaxInitialized = false;
async function ensureMathJaxReady() {
  if (!mathJaxInitialized) {
    await mathJaxReady();
    mathJaxInitialized = true;
    logger.info('MathJax initialized successfully');
  }
}

const headingLevelMap = {
  1: HeadingLevel.HEADING_1,
  2: HeadingLevel.HEADING_2,
  3: HeadingLevel.HEADING_3,
  4: HeadingLevel.HEADING_4,
  5: HeadingLevel.HEADING_5,
  6: HeadingLevel.HEADING_6
};

// Helper function to process text with formatting and math formulas
function processFormattedText(text: string): any[] {
  // First, extract and process LaTeX formulas (both inline $...$ and display $$...$$)
  // Pattern: $$formula$$ for display math, $formula$ for inline math
  // Also handle formatting: **bold**, *italic*, _italic_, `code`
  const parts = text.split(/(\$\$[^\$]+\$\$|\$[^\$]+\$|\*\*.*?\*\*|\*.*?\*|_.*?_|`.*?`)/g);

  return parts.filter(part => part.trim() !== '').flatMap((part: string): any[] => {
    // Display math: $$formula$$
    if (part.startsWith('$$') && part.endsWith('$$')) {
      let latex = part.slice(2, -2).trim();
      logger.info('Processing display math formula:', { latex: latex.substring(0, 50) });

      try {
        // Workaround: Replace \text{} with \mathrm{} as some libraries don't support \text
        // This preserves the text but uses math roman font instead
        const latexForConversion = latex.replace(/\\text\{([^}]+)\}/g, '\\mathrm{$1}');

        if (latexForConversion !== latex) {
          logger.info('Replaced \\text{} with \\mathrm{}  for conversion');
        }

        // Try to convert display formula
        const mathObj = convertLatex2Math(latexForConversion);
        logger.info('Display formula converted successfully');
        return [mathObj];
      } catch (error: any) {
        logger.error('Failed to convert display math formula, using fallback:', {
          latex,
          errorMessage: error.message || 'Unknown error',
          errorStack: error.stack
        });

        // Fallback: keep as styled text so formulas remain readable
        return [new TextRun({
          text: part, // Keep $$formula$$ format
          font: 'Courier New',
          size: 22,
          color: '0066CC' // Blue to distinguish from regular text
        })];
      }
    }
    // Inline math: $formula$
    else if (part.startsWith('$') && part.endsWith('$') && !part.startsWith('$$')) {
      const latex = part.slice(1, -1).trim();
      logger.info('Processing inline math formula:', { latex: latex.substring(0, 50) });

      try {
        const mathObj = convertLatex2Math(latex);
        return [mathObj];
      } catch (error) {
        logger.error('Failed to convert inline math formula:', { latex, error });
        // Fallback to plain text if conversion fails
        return [new TextRun({
          text: part,
          font: 'Courier New',
          size: 24
        })];
      }
    }
    // Bold: **text**
    else if (part.startsWith('**') && part.endsWith('**')) {
      return [new TextRun({
        text: part.slice(2, -2),
        bold: true,
        font: 'Arial',
        size: 24
      })];
    }
    // Italic: *text*
    else if (part.startsWith('*') && part.endsWith('*') && !part.startsWith('**')) {
      return [new TextRun({
        text: part.slice(1, -1),
        italics: true,
        font: 'Arial',
        size: 24
      })];
    }
    // Italic: _text_
    else if (part.startsWith('_') && part.endsWith('_')) {
      return [new TextRun({
        text: part.slice(1, -1),
        italics: true,
        font: 'Arial',
        size: 24
      })];
    }
    // Code: `text`
    else if (part.startsWith('`') && part.endsWith('`')) {
      return [new TextRun({
        text: part.slice(1, -1),
        font: 'Courier New',
        size: 24
      })];
    }
    // Regular text
    else {
      return [new TextRun({
        text: part,
        font: 'Arial',
        size: 24
      })];
    }
  });
}

export async function convertMarkdownToDocx(markdownContent: string): Promise<Buffer> {
  try {
    // Initialize MathJax before processing any formulas
    await ensureMathJaxReady();

    // Log sample of the markdown for debugging
    logger.info('Input markdown sample:', {
      sample: markdownContent.substring(0, Math.min(200, markdownContent.length)),
      length: markdownContent.length
    });

    // Parse markdown to tokens with GFM (GitHub Flavored Markdown) enabled
    // This enables tables, strikethrough, and other GitHub extensions
    marked.setOptions({
      gfm: true,
      breaks: false,
      pedantic: false
    });

    const tokens = marked.lexer(markdownContent);
    logger.info(`Parsed ${tokens.length} markdown tokens`);
    
    // Debug first few tokens to understand the structure
    if (tokens.length > 0) {
      logger.info('First token types:', {
        types: tokens.slice(0, Math.min(5, tokens.length)).map(t => t.type)
      });
    }
    
    const children: Paragraph[] = [];
    let lastTokenType: string | null = null;
    let consecutiveBreaks = 0;
    
    for (const token of tokens) {
      logger.info(`Processing token type: ${token.type}`);

      // Handle spacing between different content types
      if (lastTokenType && lastTokenType !== token.type) {
        if (token.type === 'space') {
          consecutiveBreaks++;
          // Only add extra space if we haven't added too many breaks already
          if (consecutiveBreaks <= 1) {
            children.push(
              new Paragraph({
                spacing: {
                  before: 80,
                  after: 80
                }
              })
            );
          }
        } else {
          consecutiveBreaks = 0;
        }
      }

      switch (token.type) {
        case 'heading': {
          consecutiveBreaks = 0;
          const headingToken = token as Tokens.Heading;
          
          children.push(
            new Paragraph({
              text: headingToken.text,
              heading: headingLevelMap[headingToken.depth as keyof typeof headingLevelMap],
              spacing: {
                before: 200,
                after: 100
              }
            })
          );
          break;
        }

        case 'paragraph': {
          consecutiveBreaks = 0;
          const paragraphToken = token as Tokens.Paragraph;
          
          // Process formatted text (bold, italic, code)
          const runs = processFormattedText(paragraphToken.text);

          children.push(
            new Paragraph({
              children: runs,
              spacing: {
                before: 60,
                after: 60,
                line: 300,
                lineRule: 'auto'
              }
            })
          );
          break;
        }

        case 'list': {
          consecutiveBreaks = 0;
          const listToken = token as Tokens.List;

          // Check if this is an ordered (numbered) or unordered (bullet) list
          const isOrdered = listToken.ordered;

          let isFirstItem = true;
          for (const item of listToken.items) {
            // Process formatted text in list items
            const runs = processFormattedText(item.text);

            // Create paragraph with appropriate list formatting
            const paragraphOptions: any = {
              children: runs,
              spacing: {
                before: isFirstItem ? 80 : 40,
                after: 40,
                line: 300,
                lineRule: 'auto'
              },
              indent: {
                left: 720,
                hanging: 360
              }
            };

            // Add bullet or numbering based on list type
            if (isOrdered) {
              paragraphOptions.numbering = {
                reference: 'default-numbering',
                level: 0
              };
            } else {
              paragraphOptions.bullet = {
                level: 0
              };
            }

            children.push(new Paragraph(paragraphOptions));
            isFirstItem = false;
          }
          break;
        }
        
        case 'blockquote': {
          consecutiveBreaks = 0;
          const blockquoteToken = token as Tokens.Blockquote;
          
          // Process each item in the blockquote
          for (const quoteToken of blockquoteToken.tokens) {
            if (quoteToken.type === 'paragraph') {
              const paraToken = quoteToken as Tokens.Paragraph;
              const runs = processFormattedText(paraToken.text);
              
              children.push(
                new Paragraph({
                  children: runs,
                  spacing: {
                    before: 60,
                    after: 60,
                    line: 300,
                    lineRule: 'auto'
                  },
                  indent: {
                    left: 720
                  },
                  border: {
                    left: {
                      color: "AAAAAA",
                      space: 15,
                      style: BorderStyle.SINGLE,
                      size: 15
                    }
                  }
                })
              );
            }
          }
          break;
        }
        
        case 'code': {
          consecutiveBreaks = 0;
          const codeToken = token as Tokens.Code;
          
          // Create a code block with monospace font using a TextRun
          children.push(
            new Paragraph({
              children: [
                new TextRun({
                  text: codeToken.text,
                  font: 'Courier New',
                  size: 20
                })
              ],
              spacing: {
                before: 80,
                after: 80,
                line: 300,
                lineRule: 'auto'
              },
              shading: {
                type: "clear",
                fill: "F5F5F5"
              }
            })
          );
          break;
        }
        
        case 'hr': {
          consecutiveBreaks = 0;
          // Add a horizontal rule
          children.push(
            new Paragraph({
              border: {
                bottom: {
                  color: "AAAAAA",
                  space: 1,
                  style: BorderStyle.SINGLE,
                  size: 1
                }
              },
              spacing: {
                before: 120,
                after: 120
              }
            })
          );
          break;
        }
        
        case 'table': {
          consecutiveBreaks = 0;
          const tableToken = token as Tokens.Table;

          // Calculate column count for width distribution
          const columnCount = tableToken.header.length;
          // Use percentage-based width for each column
          const columnWidthPercent = Math.floor(100 / columnCount);

          // Create table rows
          const rows: TableRow[] = [];

          // Define table borders (visible, professional style)
          const tableBorders = {
            top: { style: BorderStyle.SINGLE, size: 10, color: "000000" },
            bottom: { style: BorderStyle.SINGLE, size: 10, color: "000000" },
            left: { style: BorderStyle.SINGLE, size: 10, color: "000000" },
            right: { style: BorderStyle.SINGLE, size: 10, color: "000000" },
            insideHorizontal: { style: BorderStyle.SINGLE, size: 6, color: "666666" },
            insideVertical: { style: BorderStyle.SINGLE, size: 6, color: "666666" }
          };

          // Add header row with processed formatting
          const headerCells = tableToken.header.map((cell: { text: string }) => {
            // Process text with formatting (will handle **, *, _, `, formulas correctly)
            const processedRuns = processFormattedText(cell.text);

            return new TableCell({
              children: [new Paragraph({
                children: processedRuns,
                spacing: { before: 120, after: 120 }
              })],
              borders: tableBorders,
              width: { size: columnWidthPercent, type: "pct" },
              margins: {
                top: 150,
                bottom: 150,
                left: 150,
                right: 150
              },
              verticalAlign: "center" as any
            });
          });
          rows.push(new TableRow({
            children: headerCells,
            tableHeader: true,
            height: { value: 600, rule: "atLeast" as any }
          }));

          // Add data rows
          for (const row of tableToken.rows) {
            const rowCells = row.map((cell: { text: string }) => {
              return new TableCell({
                children: [new Paragraph({
                  children: processFormattedText(cell.text),
                  spacing: { before: 100, after: 100 }
                })],
                borders: tableBorders,
                width: { size: columnWidthPercent, type: "pct" },
                margins: {
                  top: 120,
                  bottom: 120,
                  left: 150,
                  right: 150
                },
                verticalAlign: "center" as any
              });
            });
            rows.push(new TableRow({
              children: rowCells,
              height: { value: 400, rule: "atLeast" as any }
            }));
          }

          // Add table to document with proper formatting
          const table = new Table({
            rows,
            width: {
              size: 100,
              type: "pct"
            },
            borders: tableBorders,
            columnWidths: Array(columnCount).fill(columnWidthPercent * 100),
            margins: {
              top: 200,
              bottom: 200,
              left: 0,
              right: 0
            }
          });

          // Tables cannot be children of paragraphs, add directly to children
          // Cast to any to work around TypeScript type checking
          (children as any[]).push(table);
          break;
        }

        case 'space':
          // Don't reset consecutiveBreaks here
          break;

        default:
          logger.info(`Unhandled token type: ${token.type}`);
          consecutiveBreaks = 0;
          break;
      }

      lastTokenType = token.type;
    }

    // Create document with some basic styling
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
                alignment: 'start',
                style: {
                  paragraph: {
                    indent: { left: 720, hanging: 360 }
                  }
                }
              }
            ]
          }
        ]
      },
      styles: {
        default: {
          document: {
            run: {
              font: 'Arial',
              size: 24
            }
          },
          heading1: {
            run: {
              size: 32,
              bold: true,
              color: "000000",
              font: 'Arial'
            },
            paragraph: {
              spacing: {
                before: 200,
                after: 100,
                line: 300,
                lineRule: 'auto'
              }
            }
          },
          heading2: {
            run: {
              size: 28,
              bold: true,
              color: "000000",
              font: 'Arial'
            },
            paragraph: {
              spacing: {
                before: 160,
                after: 80,
                line: 300,
                lineRule: 'auto'
              }
            }
          },
          heading3: {
            run: {
              size: 24,
              bold: true,
              color: "000000",
              font: 'Arial'
            },
            paragraph: {
              spacing: {
                before: 120,
                after: 60,
                line: 300,
                lineRule: 'auto'
              }
            }
          }
        },
        paragraphStyles: [
          {
            id: "codeStyle",
            name: "Code Style",
            basedOn: "Normal",
            run: {
              font: "Courier New",
              size: 20
            },
            paragraph: {
              spacing: {
                before: 80,
                after: 80,
                line: 300,
                lineRule: 'auto'
              }
            }
          }
        ]
      },
      sections: [{
        properties: {},
        children: children
      }],
    });

    logger.info(`Generated DOCX with ${children.length} paragraphs`);
    
    // Generate buffer
    return await Packer.toBuffer(doc);
  } catch (error) {
    logger.error('Error converting markdown to docx:', error);
    throw error;
  }
} 