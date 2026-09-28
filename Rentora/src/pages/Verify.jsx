// src/pages/Verify.jsx
import React, { useState, useEffect } from 'react';
import {
  Container,
  Paper,
  Typography,
  Button,
  Box,
  CircularProgress,
  Alert,
  Divider,
} from '@mui/material';
import { useLocation, useNavigate } from 'react-router-dom';
import { supabase } from '../supabaseClient';
import { useAuth } from '../context/AuthContext';

export default function Verify() {
  const { user, signOut, refreshSession } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  const [email, setEmail] = useState(
    location.state?.unconfirmedEmail || user?.email || ''
  );
  const [loadingResend, setLoadingResend] = useState(false);
  const [checkingStatus, setCheckingStatus] = useState(false);
  const [message, setMessage] = useState(location.state?.message || '');
  const [error, setError] = useState('');
  const [cooldown, setCooldown] = useState(0);

  useEffect(() => {
    if (user?.email && !email) {
      setEmail(user.email);
    }
  }, [user, email]);

  // If already confirmed, redirect to dashboard
  useEffect(() => {
    if (user?.email_confirmed_at) {
      navigate('/dashboard');
    }
  }, [user, navigate]);

  // Handle countdown for resend cooldown
  useEffect(() => {
    if (cooldown > 0) {
      const timer = setTimeout(() => setCooldown(cooldown - 1), 1000);
      return () => clearTimeout(timer);
    }
  }, [cooldown]);

  const handleResend = async () => {
    if (!email) {
      setError('No email address found to resend verification. Please try logging in again.');
      return;
    }

    setLoadingResend(true);
    setError('');
    setMessage('');

    try {
      const { error: resendError } = await supabase.auth.resend({
        type: 'signup',
        email: email.trim(),
        options: {
          emailRedirectTo: `${window.location.origin}/dashboard`,
        },
      });

      if (resendError) {
        setError(resendError.message);
      } else {
        setMessage(`Verification email has been resent to ${email}. Please check your inbox and spam folder.`);
        setCooldown(60); // 60-second cooldown to prevent rate limiting
      }
    } catch (err) {
      setError(err.message || 'Failed to resend verification email.');
    } finally {
      setLoadingResend(false);
    }
  };

  const handleCheckStatus = async () => {
    setCheckingStatus(true);
    setError('');
    setMessage('');

    try {
      const { data: { user: currentUser }, error: userError } = await supabase.auth.getUser();
      if (userError) {
        setError('Could not verify status. Please ensure you are logged in.');
      } else if (currentUser?.email_confirmed_at) {
        await refreshSession();
        navigate('/dashboard');
      } else {
        setMessage('Your email has not been confirmed yet. Please click the link in your email.');
      }
    } catch (err) {
      setError('An error occurred while checking verification status.');
    } finally {
      setCheckingStatus(false);
    }
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/login');
  };

  return (
    <Container maxWidth="sm" sx={{ py: 6 }}>
      <Paper elevation={3} sx={{ p: { xs: 3, sm: 4 } }}>
        <Box textAlign="center" mb={3}>
          <Typography variant="h4" color="primary" gutterBottom>
            Verify Institutional Email
          </Typography>
          <Typography variant="body1" color="text.secondary">
            Rentora is a trusted campus community. We require every student to verify their institutional email address before accessing the marketplace.
          </Typography>
        </Box>

        {email ? (
          <Alert severity="info" sx={{ mb: 3 }}>
            Verification link sent to: <strong>{email}</strong>
          </Alert>
        ) : (
          <Alert severity="warning" sx={{ mb: 3 }}>
            Please log in or register to verify your email.
          </Alert>
        )}

        {error && (
          <Alert severity="error" sx={{ mb: 3 }}>
            {error}
          </Alert>
        )}
        {message && (
          <Alert severity="success" sx={{ mb: 3 }}>
            {message}
          </Alert>
        )}

        <Box display="flex" flexDirection="column" gap={2} mt={2}>
          <Button
            variant="contained"
            color="primary"
            size="large"
            onClick={handleCheckStatus}
            disabled={checkingStatus}
          >
            {checkingStatus ? <CircularProgress size={24} color="inherit" /> : "I've Verified My Email"}
          </Button>

          <Button
            variant="outlined"
            color="primary"
            onClick={handleResend}
            disabled={loadingResend || cooldown > 0}
          >
            {loadingResend ? (
              <CircularProgress size={24} color="inherit" />
            ) : cooldown > 0 ? (
              `Resend Email in ${cooldown}s`
            ) : (
              'Resend Verification Email'
            )}
          </Button>

          <Divider sx={{ my: 1 }} />

          <Button
            variant="text"
            color="inherit"
            onClick={handleSignOut}
            sx={{ color: 'text.secondary' }}
          >
            Sign In with a Different Account
          </Button>
        </Box>
      </Paper>
    </Container>
  );
}
