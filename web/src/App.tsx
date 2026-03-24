import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Layout } from './components/Layout';
import { Login } from './pages/Login';
import { Dashboard } from './pages/Dashboard';
import { Vitals } from './pages/Vitals';
import { Medications } from './pages/Medications';
import { Appointments } from './pages/Appointments';
import { Documents } from './pages/Documents';
import { useAuthStore } from './store/auth';
import './i18n';
import './App.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30_000,
      refetchOnWindowFocus: false,
    },
  },
});

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated } = useAuthStore();
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

function Placeholder({ title }: { title: string }) {
  return (
    <div className="page">
      <h2>{title}</h2>
      <p>Coming soon</p>
    </div>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />

          <Route
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route path="/" element={<Dashboard />} />
            <Route path="/vitals" element={<Vitals />} />
            <Route path="/labs" element={<Placeholder title="Lab Results" />} />
            <Route path="/diary" element={<Placeholder title="Health Diary" />} />
            <Route path="/medications" element={<Medications />} />
            <Route path="/appointments" element={<Appointments />} />
            <Route path="/documents" element={<Documents />} />
            <Route path="/vaccinations" element={<Placeholder title="Vaccinations" />} />
            <Route path="/allergies" element={<Placeholder title="Allergies" />} />
            <Route path="/diagnoses" element={<Placeholder title="Diagnoses" />} />
            <Route path="/symptoms" element={<Placeholder title="Symptoms" />} />
            <Route path="/tasks" element={<Placeholder title="Tasks" />} />
            <Route path="/contacts" element={<Placeholder title="Contacts" />} />
            <Route path="/settings" element={<Placeholder title="Settings" />} />
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}

export default App;
