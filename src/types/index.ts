export interface MarkdownRequest {
  output: string;
  fileName?: string;
  folderId?: string;
  webhookUrl?: string;
  executionMode?: string;
}

export interface GoogleDocResponse {
  documentId: string;
  url: string;
  status: number;
  fileName: string;
  folderId?: string;
  webhookUrl?: string;
  executionMode?: string;
}

export interface ErrorResponse {
  error: string;
  details?: string;
  status: number;
}

export interface FormattedRange {
  text: string;
  index: number;
  length: number;
  fullMatch: string;
}

export interface GoogleDocsRequest {
  title: string;
}

export interface GoogleDocsUpdateRequest {
  documentId: string;
  requestBody: {
    requests: any[];
  };
} 