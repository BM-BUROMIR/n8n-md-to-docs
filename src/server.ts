/**
 * Standalone Express server for production deployment
 * This runs the Express app directly without Firebase Functions wrapper
 */
import express from 'express';
import cors from 'cors';
import type { Request, Response } from 'express';
import type { MarkdownRequest, GoogleDocResponse, ErrorResponse } from './types';
import { convertMarkdownToGoogleDoc } from './services/googleDocs';

const app = express();
const PORT = process.env.PORT || 8080;

// Middleware
app.use(express.json({ limit: '10mb' }));
app.use(cors({ origin: true }));

// Health check endpoint
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'md2doc-converter' });
});

// Main conversion endpoint
app.post('/', async (req: Request, res: Response) => {
  try {
    console.log('Received request:', {
      hasBody: !!req.body,
      hasAuth: !!req.headers.authorization
    });

    // Handle array of requests
    const requests: MarkdownRequest[] = Array.isArray(req.body) ? req.body : [req.body];
    console.log(`Processing ${requests.length} request(s)`);

    const results = await Promise.all(requests.map(async (request, index) => {
      // Extract request data
      const markdownContent = request.output;
      const authHeader = req.headers.authorization;
      const fileName = request.fileName || 'Converted from Markdown';
      const folderId = request.folderId;

      console.log(`Request ${index + 1} validation:`, {
        hasMarkdown: !!markdownContent,
        contentLength: markdownContent?.length,
        hasAuthHeader: !!authHeader,
        fileName,
        folderId: folderId || 'root (default)'
      });

      // Validate markdown content
      if (!markdownContent) {
        console.error(`Request ${index + 1}: Missing markdown content`);
        return {
          error: 'Missing required field: output',
          status: 400,
          request: {
            ...request,
            output: undefined
          }
        } as ErrorResponse;
      }

      // Validate authorization
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        console.error(`Request ${index + 1}: Invalid authorization`);
        return {
          error: 'Missing or invalid authorization header',
          status: 401
        } as ErrorResponse;
      }

      const accessToken = authHeader.split(' ')[1];

      try {
        console.log(`Request ${index + 1}: Starting conversion for "${fileName}"`);
        const result = await convertMarkdownToGoogleDoc(markdownContent, accessToken, fileName, folderId);
        console.log(`Request ${index + 1}: Conversion successful:`, result);

        return {
          ...result,
          webhookUrl: request.webhookUrl,
          executionMode: request.executionMode
        } as GoogleDocResponse;
      } catch (error: any) {
        console.error(`Request ${index + 1}: Conversion failed:`, {
          error: error.message,
          status: error.status || error.code,
          details: error.errors || error.stack
        });

        return {
          error: 'Failed to convert markdown to Google Doc',
          details: error.message,
          status: error.status || 500
        } as ErrorResponse;
      }
    }));

    // Send response
    if (results.length === 1) {
      const result = results[0];
      console.log('Sending single response:', {
        ...result,
        documentContent: undefined
      });
      return res.status(result.status).json(result);
    }

    console.log('Sending multiple responses:', results.length);
    return res.json(results);

  } catch (error: any) {
    console.error('Fatal error processing requests:', {
      error: error.message,
      stack: error.stack
    });

    return res.status(500).json({
      error: 'Failed to process requests',
      details: error.message
    } as ErrorResponse);
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 md2doc-converter server running on port ${PORT}`);
  console.log(`📝 POST requests to: http://localhost:${PORT}/`);
  console.log(`💚 Health check: http://localhost:${PORT}/health`);
});
