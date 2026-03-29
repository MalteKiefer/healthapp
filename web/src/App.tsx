import { lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ErrorBoundary } from './components/ErrorBoundary';
import { Layout } from './components/Layout';
import { useAuthStore } from './store/auth';
import './i18n';
import './App.css';

// Lazy-loaded pages — code-split per route
const Login = lazy(() => import('./pages/Login').then((m) => ({ default: m.Login })));
const Register = lazy(() => import('./pages/Register').then((m) => ({ default: m.Register })));
const Recovery = lazy(() => import('./pages/Recovery').then((m) => ({ default: m.Recovery })));
const Dashboard = lazy(() => import('./pages/Dashboard').then((m) => ({ default: m.Dashboard })));
const Vitals = lazy(() => import('./pages/Vitals').then((m) => ({ default: m.Vitals })));
const Labs = lazy(() => import('./pages/Labs').then((m) => ({ default: m.Labs })));
const Medications = lazy(() => import('./pages/Medications').then((m) => ({ default: m.Medications })));
const Appointments = lazy(() => import('./pages/Appointments').then((m) => ({ default: m.Appointments })));
const Documents = lazy(() => import('./pages/Documents').then((m) => ({ default: m.Documents })));
const Diary = lazy(() => import('./pages/Diary').then((m) => ({ default: m.Diary })));
const Settings = lazy(() => import('./pages/Settings').then((m) => ({ default: m.Settings })));
const Vaccinations = lazy(() => import('./pages/Vaccinations').then((m) => ({ default: m.Vaccinations })));
const Allergies = lazy(() => import('./pages/Allergies').then((m) => ({ default: m.Allergies })));
const Diagnoses = lazy(() => import('./pages/Diagnoses').then((m) => ({ default: m.Diagnoses })));
const Tasks = lazy(() => import('./pages/Tasks').then((m) => ({ default: m.Tasks })));
const Contacts = lazy(() => import('./pages/Contacts').then((m) => ({ default: m.Contacts })));
const Symptoms = lazy(() => import('./pages/Symptoms').then((m) => ({ default: m.Symptoms })));
const Onboarding = lazy(() => import('./pages/Onboarding').then((m) => ({ default: m.Onboarding })));
const ShareView = lazy(() => import('./pages/ShareView').then((m) => ({ default: m.ShareView })));
const NotFound = lazy(() => import('./pages/NotFound').then((m) => ({ default: m.NotFound })));
const Search = lazy(() => import('./pages/Search').then((m) => ({ default: m.Search })));
const Admin = lazy(() => import('./pages/Admin').then((m) => ({ default: m.Admin })));
const CalendarFeeds = lazy(() => import('./pages/CalendarFeeds').then((m) => ({ default: m.CalendarFeeds })));
const Family = lazy(() => import('./pages/Family').then((m) => ({ default: m.Family })));
const DoctorShares = lazy(() => import('./pages/DoctorShares').then((m) => ({ default: m.DoctorShares })));
const EmergencyAccess = lazy(() => import('./pages/EmergencyAccess').then((m) => ({ default: m.EmergencyAccess })));
const Export = lazy(() => import('./pages/Export').then((m) => ({ default: m.Export })));
const ActivityLog = lazy(() => import('./pages/ActivityLog').then((m) => ({ default: m.ActivityLog })));

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

function Loading() {
  return <div className="page" style={{ textAlign: 'center', paddingTop: 80 }}>Loading...</div>;
}

function App() {
  return (
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <Suspense fallback={<Loading />}>
            <Routes>
              <Route path="/login" element={<Login />} />
              <Route path="/register" element={<Register />} />
              <Route path="/recovery" element={<Recovery />} />
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
                <Route path="/search" element={<Search />} />
                <Route path="/admin" element={<Admin />} />
                <Route path="/calendar-feeds" element={<CalendarFeeds />} />
                <Route path="/family" element={<Family />} />
                <Route path="/shares" element={<DoctorShares />} />
                <Route path="/emergency" element={<EmergencyAccess />} />
                <Route path="/export" element={<Export />} />
                <Route path="/activity" element={<ActivityLog />} />
              </Route>

              <Route path="*" element={<NotFound />} />
            </Routes>
          </Suspense>
        </BrowserRouter>
      </QueryClientProvider>
    </ErrorBoundary>
  );
}

export default App;
