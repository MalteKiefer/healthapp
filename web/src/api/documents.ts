import { api } from './client';

export interface Document {
  id: string;
  profile_id: string;
  filename: string;
  mime_type: string;
  file_size_bytes: number;
  category: string;
  tags?: string[];
  ocr_text?: string;
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
  update: (profileId: string, id: string, data: Partial<Document>) =>
    api.patch<Document>(`/api/v1/profiles/${profileId}/documents/${id}`, data),
  downloadUrl: (profileId: string, id: string) =>
    `/api/v1/profiles/${profileId}/documents/${id}/download`,
  upload: async (profileId: string, file: File, category: string) => {
    const formData = new FormData();
    formData.append('category', category);
    formData.append('file', file);
    formData.append('filename', file.name);

    return api.postFormData<Document>(
      `/api/v1/profiles/${profileId}/documents`,
      formData,
    );
  },
};
