import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';

/**
 * ShareView — Doctor's view of shared health data.
 *
 * URL: /share/{shareID}#base64TempKey
 * The fragment (#tempKey) never reaches the server.
 * The browser fetches the encrypted bundle and decrypts locally.
 */
export function ShareView() {
  const { shareID } = useParams<{ shareID: string }>();
  const [status, setStatus] = useState<'loading' | 'decrypting' | 'ready' | 'error' | 'expired'>('loading');
  const [error, setError] = useState('');
  const [data, setData] = useState<Record<string, unknown> | null>(null);

  useEffect(() => {
    if (!shareID) return;

    const fragment = window.location.hash.slice(1); // Remove #
    if (!fragment) {
      setStatus('error');
      setError('No decryption key found in URL. The share link may be incomplete.');
      return;
    }

    fetchAndDecrypt(shareID, fragment);
  }, [shareID]);

  async function fetchAndDecrypt(id: string, keyBase64: string) {
    try {
      // Fetch encrypted bundle from server
      const res = await fetch(`/share/${id}`);
      if (res.status === 410) {
        setStatus('expired');
        return;
      }
      if (!res.ok) {
        setStatus('error');
        setError('Share not found or has expired.');
        return;
      }

      const bundle = await res.json();
      setStatus('decrypting');

      // Decode the temp key from the fragment
      const keyBytes = Uint8Array.from(atob(keyBase64), (c) => c.charCodeAt(0));

      // Import as AES-GCM key
      const tempKey = await crypto.subtle.importKey(
        'raw',
        keyBytes,
        { name: 'AES-GCM', length: 256 },
        false,
        ['decrypt'],
      );

      // Decrypt the bundle
      const encryptedData = bundle.encrypted_data;
      const combined = Uint8Array.from(atob(encryptedData), (c) => c.charCodeAt(0));
      const iv = combined.slice(0, 12);
      const ciphertext = combined.slice(12);

      const plaintext = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv, tagLength: 128 },
        tempKey,
        ciphertext,
      );

      const decoded = new TextDecoder().decode(plaintext);
      setData(JSON.parse(decoded));
      setStatus('ready');
    } catch (err) {
      setStatus('error');
      setError('Failed to decrypt. The link may be invalid or corrupted.');
      console.error('Share decryption error:', err);
    }
  }

  if (status === 'loading') {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h1>HealthVault</h1>
          <p className="auth-tagline">Loading shared health data...</p>
        </div>
      </div>
    );
  }

  if (status === 'decrypting') {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h1>HealthVault</h1>
          <p className="auth-tagline">Decrypting data in your browser...</p>
        </div>
      </div>
    );
  }

  if (status === 'expired') {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h1>HealthVault</h1>
          <p className="auth-tagline">This share link has expired or been revoked.</p>
        </div>
      </div>
    );
  }

  if (status === 'error') {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <h1>HealthVault</h1>
          <div className="alert alert-error">{error}</div>
        </div>
      </div>
    );
  }

  // Render decrypted health data
  return (
    <div className="auth-page" style={{ alignItems: 'flex-start', paddingTop: 40 }}>
      <div style={{ maxWidth: 800, width: '100%' }}>
        <div className="card" style={{ marginBottom: 16 }}>
          <h2>Shared Health Summary</h2>
          <p className="text-muted">
            This is a read-only view of shared health data. It was decrypted locally in your browser.
          </p>
        </div>

        {data && typeof data === 'object' && (
          <>
            {renderSection('Medications', data.medications as unknown[])}
            {renderSection('Allergies', data.allergies as unknown[])}
            {renderSection('Diagnoses', data.diagnoses as unknown[])}
            {renderSection('Vitals', data.vitals as unknown[])}
            {renderSection('Contacts', data.contacts as unknown[])}
          </>
        )}

        <div className="card" style={{ textAlign: 'center' }}>
          <p className="text-muted">
            Powered by HealthVault — Zero-knowledge health data management
          </p>
        </div>
      </div>
    </div>
  );
}

function renderSection(title: string, items: unknown[] | undefined) {
  if (!items || !Array.isArray(items) || items.length === 0) return null;

  return (
    <div className="card" style={{ marginBottom: 16 }}>
      <h3>{title}</h3>
      <div className="table-scroll">
        <table className="data-table">
          <thead>
            <tr>
              {Object.keys(items[0] as Record<string, unknown>)
                .filter((k) => !k.endsWith('_id') && k !== 'id' && !k.endsWith('_enc'))
                .map((key) => (
                  <th key={key}>{key.replace(/_/g, ' ')}</th>
                ))}
            </tr>
          </thead>
          <tbody>
            {items.map((item, i) => (
              <tr key={i}>
                {Object.entries(item as Record<string, unknown>)
                  .filter(([k]) => !k.endsWith('_id') && k !== 'id' && !k.endsWith('_enc'))
                  .map(([k, v]) => (
                    <td key={k}>{String(v ?? '—')}</td>
                  ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
