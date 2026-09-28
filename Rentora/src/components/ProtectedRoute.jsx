// src/components/ProtectedRoute.jsx
import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { CircularProgress, Box, Typography } from '@mui/material';

/**
 * ProtectedRoute guards routes requiring an authenticated and verified campus user.
 * Redirects unauthenticated users to /login and unverified users to /verify.
 */
export default function ProtectedRoute({ children }) {
  const { session, user, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return (
      <Box
        display="flex"
        flexDirection="column"
        alignItems="center"
        justifyContent="center"
        minHeight="50vh"
      >
        <CircularProgress size={36} />
        <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>
          Checking campus authorization...
        </Typography>
      </Box>
    );
  }

  // 1. Not authenticated -> redirect to login
  if (!session || !user) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  // 2. Authenticated but email unverified -> redirect to verification page
  if (!user.email_confirmed_at) {
    return (
      <Navigate
        to="/verify"
        state={{
          unconfirmedEmail: user.email,
          message: 'Your institutional email must be verified to access protected campus areas.',
          from: location,
        }}
        replace
      />
    );
  }

  // 3. Authenticated and verified -> render protected view
  return children;
}
