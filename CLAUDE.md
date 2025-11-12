# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**n8n-md-to-docs** is a Firebase Cloud Function that converts Markdown content to Google Docs format, designed specifically for n8n workflow integration. The service accepts markdown text (typically from LLM outputs) and creates properly formatted Google Docs using n8n's Google OAuth credentials.

**Technology Stack:** TypeScript, Firebase Functions v2, Express.js, Bun runtime, Google APIs, docx library, marked parser

**Hosted Service:** `https://md2doc.n8n.aemalsayer.com`

## Architecture

### Core Conversion Flow

The service implements a two-stage conversion process:

1. **Markdown → DOCX** (src/services/docxConverter.ts:57)
   - Parses markdown using `marked` lexer to extract tokens
   - Converts tokens to `docx` library elements (Paragraph, TextRun, etc.)
   - Handles: headings (H1-H6), paragraphs, lists, blockquotes, code blocks, tables, horizontal rules
   - Processes inline formatting: **bold**, *italic*, `code`
   - Applies consistent styling (Arial font, spacing, indentation)

2. **DOCX → Google Docs** (src/services/googleDocs.ts:7)
   - Converts DOCX buffer to Google Docs using Google Drive API
   - Uses `mimeType: 'application/vnd.google-apps.document'` for automatic conversion
   - Authenticates with n8n's OAuth token passed in Authorization header

### Request Processing (src/index.ts:16)

- Accepts single request or array of requests for batch processing
- Validates: markdown content (`output` field) and OAuth token (Bearer header)
- Returns document ID and URL on success
- Includes comprehensive logging at each stage for debugging

### Key Design Decisions

1. **Two-stage conversion**: Direct markdown-to-Google Docs is not possible via Google APIs. The intermediate DOCX format preserves rich formatting that Google Docs can interpret correctly.

2. **Code block unwrapping** (src/services/googleDocs.ts:19-26): Automatically strips markdown code fence wrappers (` ```markdown ` or ` ``` `) that LLMs often add.

3. **Memory allocation** (src/index.ts:155): Function configured with 1GB memory (up from default 256MB) to handle large markdown documents and concurrent processing.

## Development Commands

### Build & Deploy
```bash
# Build TypeScript to lib/ directory
bun run build

# Watch mode for development
bun run build:watch

# Local development with Firebase emulator
bun run serve         # Runs on localhost:5001

# Deploy to Firebase
bun run deploy

# View function logs
bun run logs
```

### Local Development
```bash
# Start with hot reload (direct Bun execution)
bun run dev

# Test the function shell
bun run shell
```

### Environment Setup
```bash
# Login to Firebase
firebase login

# Initialize Firebase project
firebase init functions

# Set up emulators
firebase init emulators
```

## Configuration Files

### firebase.json
- **Functions source**: `lib/` (compiled output)
- **Runtime**: Node.js 22
- **Region**: us-central1
- **Function name**: `mdToGoogleDoc`
- **Hosting**: Rewrites all traffic to the function
- **Emulator port**: 5001

### tsconfig.json
- **Module system**: ESNext with Bundler resolution
- **Target**: ES2022
- **Strict mode**: Enabled with strict TypeScript checks

### package.json
- **Build**: Bun compiles `src/index.ts` → `lib/`, then copies package.json to lib/
- **Node engine**: 22 (Firebase requirement)
- **Module type**: ESM

## Request/Response Format

### Request Body
```json
{
  "output": "# Markdown content here",
  "fileName": "Optional Document Name",
  "webhookUrl": "Optional webhook for notifications",
  "executionMode": "Optional mode flag"
}
```

Can send single object or array for batch processing.

### Required Header
```
Authorization: Bearer <n8n_google_oauth_token>
```

### Success Response
```json
{
  "documentId": "1abc...",
  "url": "https://docs.google.com/document/d/1abc...",
  "status": 200,
  "fileName": "Document Name"
}
```

### Error Response
```json
{
  "error": "Error message",
  "details": "Detailed error description",
  "status": 400|401|500
}
```

## Testing

### Test Endpoint (src/index.ts:119)
A `/test` POST endpoint exists for development testing that:
- Does NOT require OAuth authentication
- Returns raw DOCX buffer instead of creating Google Doc
- Only available when `NODE_ENV !== 'production'`
- Useful for debugging markdown-to-DOCX conversion issues

```bash
# Test conversion locally
curl -X POST http://localhost:5001/test \
  -H "Content-Type: application/json" \
  -d '{"markdown": "# Test", "fileName": "test.docx"}'
```

## Common Development Tasks

### Adding New Markdown Features
1. Update token handler in `src/services/docxConverter.ts` switch statement (line 103)
2. Use `marked` token types from `import type { Tokens } from 'marked'`
3. Convert to appropriate `docx` elements (Paragraph, Table, etc.)
4. Add styling in document styles object (line 324)

### Debugging Conversion Issues
- Check Firebase logs: `bun run logs`
- Look for token type logs: "Processing token type: X"
- Verify DOCX buffer size is non-zero
- Test with `/test` endpoint to isolate markdown parsing issues
- Review first few tokens: "First token types" log entry

### Modifying Document Styling
All styling is centralized in the `Document` constructor (src/services/docxConverter.ts:323):
- Default document styles (font, size)
- Heading styles (H1-H3 explicitly defined)
- Paragraph styles (code blocks, spacing)
- Modify spacing, fonts, colors, and borders here

## Project Structure
```
src/
├── index.ts                    # Express app & Firebase function export
├── services/
│   ├── docxConverter.ts        # Markdown → DOCX conversion
│   └── googleDocs.ts           # DOCX → Google Docs via Drive API
└── types/
    └── index.ts                # TypeScript interfaces

lib/                            # Compiled output (git-ignored)
public/                         # Static hosting files
firebase.json                   # Firebase configuration
tsconfig.json                   # TypeScript configuration
bun.lock                        # Bun package lock
```

## Firebase Function Configuration

The exported function (src/index.ts:154) uses Firebase Functions v2 with:
- **Memory**: 1GiB (increased for large documents)
- **Timeout**: 300 seconds (5 minutes)
- **Concurrency**: 30 (max parallel executions per instance)
- **Max instances**: 50
- **CORS**: Enabled for browser requests

## n8n Integration Pattern

When integrating with n8n workflows:
1. **HTTP Request node** with method POST
2. **Authentication**: Use "Predefined Credential Type" → "Google Docs OAuth2 API"
3. **Body**: JSON with `output` (markdown string) and `fileName` fields
4. **Expression variables**: Can use `{{$json.output}}` from previous nodes (like LLM outputs)
5. **Response**: Contains `documentId` and `url` for further workflow use

## Dependencies

### Production
- **express**: HTTP server framework
- **firebase-functions**: Cloud Functions runtime
- **firebase-admin**: Firebase Admin SDK
- **googleapis**: Google Drive/Docs API client
- **docx**: DOCX document generation
- **marked**: Markdown parser
- **cors**: CORS middleware

### Development
- **bun**: JavaScript runtime and package manager
- **@types/***: TypeScript type definitions
- **firebase-functions-test**: Testing framework

## Important Notes

1. **Bun for build, Node for runtime**: Development uses Bun for fast builds, but Firebase executes with Node.js 22
2. **ESM modules**: Project uses ES modules (`type: "module"` in package.json)
3. **Automatic wrapper stripping**: Service automatically removes markdown code fences that LLMs often add
4. **Batch processing**: Can process multiple markdown documents in a single request by sending an array
5. **Comprehensive logging**: Every step logs to Firebase Functions logger for debugging production issues
