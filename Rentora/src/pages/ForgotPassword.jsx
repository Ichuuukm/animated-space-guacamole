// src/pages/ForgotPassword.jsx
import React, { useState } from 'react';
import {
  Container,
  Paper,
  TextField,
  Button,
  Typography,
  Box,
  CircularProgress,
  Alert,
} from '@mui/material';
import { Link } from 'react-router-dom';
import { supabase } from '../supabaseClient';

export default function ForgotPassword() {
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setMessage('');

    if (!email.trim()) {
      setError('Please provide your institutional email address.');
      return;
    }

    setLoading(true);

    try {
      const { error: supabaseError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: `${window.location.origin}/reset-password`,
      });

      if (supabaseError) {
        setError(supabaseError.message);
      } else {
        setMessage(
          `Password reset instructions have been sent to ${email.trim()}. Please check your institutional email inbox.`
        );
      }
    } catch (err) {
      setError(err.message || 'An unexpected error occurred while requesting password reset.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Container maxWidth="sm" sx={{ py: 6 }}>
      <Paper elevation={3} sx={{ p: { xs: 3, sm: 4 } }}>
        <Box textAlign="center" mb={3}>
          <Typography variant="h4" color="primary" gutterBottom>
            Reset Your Password
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Enter your registered institutional email to receive a password recovery link.
          </Typography>
        </Box>

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

        <Box component="form" onSubmit={handleSubmit} noValidate>
          <TextField
            label="Institutional Email"
            type="email"
            fullWidth
            margin="normal"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="student@university.edu"
            required
            autoComplete="email"
          />

          <Button
            type="submit"
            variant="contained"
            color="primary"
            fullWidth
            size="large"
            disabled={loading}
            sx={{ mt: 3, py: 1.2 }}
          >
            {loading ? <CircularProgress size={26} color="inherit" /> : 'Send Reset Link'}
          </Button>

          <Box mt={3} textAlign="center">
            <Typography variant="body2">
              Remember your password?{' '}
              <Link to="/login" style={{ color: '#1E3A8A', fontWeight: 600 }}>
                Back to Login
              </Link>
            </Typography>
          </Box>
        </Box>
      </Paper>
    </Container>
  );
}
