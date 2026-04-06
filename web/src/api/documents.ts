import { api } from './client';
import { getProfileKey } from '../crypto/keys';
import { encryptFile, encryptString } from '../crypto/encrypt';

export interface Document {
  id: string;
  profile_id: string;
  filename_enc: string;
  mime_type: string;
  file_size_bytes: number;
  category: string;
  tags?: string[];
  encrypted_at?: string;
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
  // Upload handled separately with multipart form
  upload: async (profileId: string, file: File, category: string) => {
    const formData = new FormData();
    formData.append('category', category);

    const profileKey = getProfileKey(profileId);
    if (profileKey) {
      // Encrypt file content and filename before upload
      const encryptedBlob = await encryptFile(file, profileKey);
      const encryptedFilename = await encryptString(file.name, profileKey);
      formData.append('file', encryptedBlob, 'encrypted');
      formData.append('filename_enc', encryptedFilename);
      formData.append('encrypted', 'true');
    } else {
      // Legacy path: no profile key available, upload raw
      formData.append('file', file);
    }

    const res = await fetch(`/api/v1/profiles/${profileId}/documents`, {
      method: 'POST',
      credentials: 'include',
      body: formData,
    });

    if (!res.ok) throw new Error('Upload failed');
    return res.json() as Promise<Document>;
  },
};
