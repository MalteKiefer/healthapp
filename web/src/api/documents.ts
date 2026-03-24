import { api } from './client';

export interface Document {
  id: string;
  profile_id: string;
  filename_enc: string;
  mime_type: string;
  file_size_bytes: number;
  category: string;
  tags?: string[];
  created_at: string;
}

export interface DocumentListResponse {
  items: Document[];
  total: number;
}

export const documentsApi = {
  list: (profileId: string) =>
    api.get<DocumentListResponse>(`/api/v1/profiles/${profileId}/documents`),
  get: (profileId: string, id: string) =>
    api.get<Document>(`/api/v1/profiles/${profileId}/documents/${id}`),
  delete: (profileId: string, id: string) =>
    api.delete(`/api/v1/profiles/${profileId}/documents/${id}`),
  // Upload handled separately with multipart form
  upload: async (profileId: string, file: File, category: string) => {
    const token = localStorage.getItem('access_token');
    const formData = new FormData();
    formData.append('file', file);
    formData.append('category', category);

    const res = await fetch(`/api/v1/profiles/${profileId}/documents`, {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: formData,
    });

    if (!res.ok) throw new Error('Upload failed');
    return res.json() as Promise<Document>;
  },
};
