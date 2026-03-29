import { Component, type ReactNode } from 'react';
import i18n from '../i18n';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('ErrorBoundary caught:', error, info);
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;

      const t = i18n.t.bind(i18n);
      return (
        <div className="error-boundary">
          <div className="error-card">
            <h2>{t('error_boundary.title')}</h2>
            <p className="text-muted">
              {this.state.error?.message || t('error_boundary.default_message')}
            </p>
            <button
              className="btn btn-add"
              onClick={() => {
                this.setState({ hasError: false, error: null });
                window.location.reload();
              }}
            >
              {t('error_boundary.reload')}
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
