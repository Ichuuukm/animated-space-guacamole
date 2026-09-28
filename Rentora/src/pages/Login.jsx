// src/pages/Login.jsx
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
  InputAdornment,
} from '@mui/material';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../supabaseClient';

export default function Login() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (!email.trim() || !password) {
      setError('Please provide both email and password.');
      return;
    }

    setLoading(true);

    try {
      const { data, error: supabaseError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (supabaseError) {
        setError(supabaseError.message);
        return;
      }

      // Check if email has been verified
      if (data?.user && !data.user.email_confirmed_at) {
        navigate('/verify', {
          state: {
            unconfirmedEmail: data.user.email,
            message: 'Please verify your institutional email before accessing your account.',
          },
        });
      } else {
        navigate('/dashboard');
      }
    } catch (err) {
      setError(err.message || 'An unexpected error occurred while logging in.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Container maxWidth="sm" sx={{ py: 6 }}>
      <Paper elevation={3} sx={{ p: { xs: 3, sm: 4 } }}>
        <Box textAlign="center" mb={3}>
          <Typography variant="h4" color="primary" gutterBottom>
            Welcome Back
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Sign in to access your campus marketplace
          </Typography>
        </Box>

        {error && (
          <Alert severity="error" sx={{ mb: 3 }}>
            {error}
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

          <TextField
            label="Password"
            type={showPassword ? 'text' : 'password'}
            fullWidth
            margin="normal"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete="current-password"
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

          <Box display="flex" justifyContent="flex-end" mt={1}>
            <Typography variant="body2">
              <Link to="/forgot" style={{ color: '#1E3A8A', textDecoration: 'none' }}>
                Forgot password?
              </Link>
            </Typography>
          </Box>

          <Button
            type="submit"
            variant="contained"
            color="primary"
            fullWidth
            size="large"
            disabled={loading}
            sx={{ mt: 3, py: 1.2 }}
          >
            {loading ? <CircularProgress size={26} color="inherit" /> : 'Sign In'}
          </Button>

          <Box mt={3} textAlign="center">
            <Typography variant="body2">
              Don't have an account?{' '}
              <Link to="/register" style={{ color: '#1E3A8A', fontWeight: 600 }}>
                Register with your campus email
              </Link>
            </Typography>
          </Box>
        </Box>
      </Paper>
    </Container>
  );
}
