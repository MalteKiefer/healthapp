import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Layout } from './components/Layout';
import { Login } from './pages/Login';
import { Dashboard } from './pages/Dashboard';
import { Vitals } from './pages/Vitals';
import { Labs } from './pages/Labs';
import { Medications } from './pages/Medications';
import { Appointments } from './pages/Appointments';
import { Documents } from './pages/Documents';
import { Diary } from './pages/Diary';
import { Settings } from './pages/Settings';
import { Vaccinations } from './pages/Vaccinations';
import { Allergies } from './pages/Allergies';
import { Diagnoses } from './pages/Diagnoses';
import { Tasks } from './pages/Tasks';
import { Contacts } from './pages/Contacts';
import { Symptoms } from './pages/Symptoms';
import { Onboarding } from './pages/Onboarding';
import { ShareView } from './pages/ShareView';
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

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/onboarding" element={<Onboarding />} />
          <Route path="/share/:shareID" element={<ShareView />} />

          <Route
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route path="/" element={<Dashboard />} />
            <Route path="/vitals" element={<Vitals />} />
            <Route path="/labs" element={<Labs />} />
            <Route path="/diary" element={<Diary />} />
            <Route path="/medications" element={<Medications />} />
            <Route path="/appointments" element={<Appointments />} />
            <Route path="/documents" element={<Documents />} />
            <Route path="/vaccinations" element={<Vaccinations />} />
            <Route path="/allergies" element={<Allergies />} />
            <Route path="/diagnoses" element={<Diagnoses />} />
            <Route path="/symptoms" element={<Symptoms />} />
            <Route path="/tasks" element={<Tasks />} />
            <Route path="/contacts" element={<Contacts />} />
            <Route path="/settings" element={<Settings />} />
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}

export default App;
