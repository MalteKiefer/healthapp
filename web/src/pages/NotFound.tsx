import { Link } from 'react-router-dom';

export function NotFound() {
  return (
    <div className="auth-page">
      <div className="auth-card" style={{ textAlign: 'center' }}>
        <h1 style={{ fontSize: 64, marginBottom: 8 }}>404</h1>
        <p className="auth-tagline">Page not found</p>
        <Link to="/" className="btn btn-add" style={{ display: 'inline-block', width: 'auto', marginTop: 16 }}>
          Go to Dashboard
        </Link>
      </div>
    </div>
  );
}
