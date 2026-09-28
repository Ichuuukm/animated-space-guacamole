// src/pages/ResetPassword.jsx
import React, { useState, useEffect } from 'react';
import {
  Container,
  Paper,
  TextField,
  Button,
  Typography,
  Box,
  CircularProgress,
  Alert,
  InputAdornment,
} from '@mui/material';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { supabase } from '../supabaseClient';
import { useAuth } from '../context/AuthContext';

export default function ResetPassword() {
  const navigate = useNavigate();
  const location = useLocation();
  const { session } = useAuth();

  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [verifyingSession, setVerifyingSession] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    let isMounted = true;

    async function evaluateRecoverySession() {
      try {
        // 1. Check if user already has an active session from recovery link
        const { data: { session: currentSession } } = await supabase.auth.getSession();
        if (currentSession) {
          if (isMounted) setVerifyingSession(false);
          return;
        }

        // 2. Check hash fragments (#access_token=...&refresh_token=...)
        const hash = window.location.hash.substring(1);
        if (hash) {
          const params = new URLSearchParams(hash);
          const accessToken = params.get('access_token');
          const refreshToken = params.get('refresh_token');

          if (accessToken && refreshToken) {
            const { error: sessionError } = await supabase.auth.setSession({
              access_token: accessToken,
              refresh_token: refreshToken,
            });
            if (sessionError && isMounted) {
              setError('Recovery link is invalid or has expired. Please request a new reset link.');
            }
          }
        }

        // 3. Check query parameters (?code=... for PKCE flow)
        const searchParams = new URLSearchParams(location.search);
        const code = searchParams.get('code');
        if (code) {
          const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
          if (exchangeError && isMounted) {
            setError('Recovery code exchange failed. Please request a new link.');
          }
        }
      } catch (err) {
        if (isMounted) {
          setError('Failed to establish password reset session.');
        }
      } finally {
        if (isMounted) {
          setVerifyingSession(false);
        }
      }
    }

    evaluateRecoverySession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY') {
        if (isMounted) {
          setVerifyingSession(false);
        }
      }
    });

    return () => {
      isMounted = false;
      subscription?.unsubscribe();
    };
  }, [location]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (!newPassword) {
      setError('Please provide a new password.');
      return;
    }
    if (newPassword.length < 6) {
      setError('Password must be at least 6 characters.');
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);

    try {
      const { error: updateError } = await supabase.auth.updateUser({
        password: newPassword,
      });

      if (updateError) {
        setError(updateError.message);
      } else {
        setSuccess(true);
        setTimeout(() => {
          navigate('/login');
        }, 2000);
      }
    } catch (err) {
      setError(err.message || 'Failed to update password.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Container maxWidth="sm" sx={{ py: 6 }}>
      <Paper elevation={3} sx={{ p: { xs: 3, sm: 4 } }}>
        <Box textAlign="center" mb={3}>
          <Typography variant="h4" color="primary" gutterBottom>
            Create New Password
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Set a new secure password for your Rentora account.
          </Typography>
        </Box>

        {verifyingSession ? (
          <Box display="flex" flexDirection="column" alignItems="center" py={4}>
            <CircularProgress size={32} />
            <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>
              Verifying security session...
            </Typography>
          </Box>
        ) : (
          <>
            {error && (
              <Alert severity="error" sx={{ mb: 3 }}>
                {error}
              </Alert>
            )}
            {success && (
              <Alert severity="success" sx={{ mb: 3 }}>
                Password updated successfully! Redirecting you to login...
              </Alert>
            )}

            <Box component="form" onSubmit={handleSubmit} noValidate>
              <TextField
                label="New Password"
                type={showPassword ? 'text' : 'password'}
                fullWidth
                margin="normal"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                helperText="Minimum 6 characters"
                required
                InputProps={{
                  endAdornment: (
                    <InputAdornment position="end">
                      <Button
                        size="small"
                        onClick={() => setShowPassword(!showPassword)}
                        tabIndex={-1}
                      >
                        {showPassword ? 'Hide' : 'Show'}
                      </Button>
                    </InputAdornment>
                  ),
                }}
              />

              <TextField
                label="Confirm New Password"
                type={showPassword ? 'text' : 'password'}
                fullWidth
                margin="normal"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
              />

              <Button
                type="submit"
                variant="contained"
                color="primary"
                fullWidth
                size="large"
                disabled={loading || success}
                sx={{ mt: 3, py: 1.2 }}
              >
                {loading ? <CircularProgress size={26} color="inherit" /> : 'Update Password'}
              </Button>

              <Box mt={3} textAlign="center">
                <Typography variant="body2">
                  Return to{' '}
                  <Link to="/login" style={{ color: '#1E3A8A', fontWeight: 600 }}>
                    Login
                  </Link>
                </Typography>
              </Box>
            </Box>
          </>
        )}
      </Paper>
    </Container>
  );
}
