// src/pages/Register.jsx
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
  Chip,
  IconButton,
  InputAdornment,
} from '@mui/material';
import { useNavigate, Link } from 'react-router-dom';
import { supabase } from '../supabaseClient';

const PUBLIC_EMAIL_DOMAINS = [
  'gmail.com',
  'yahoo.com',
  'hotmail.com',
  'outlook.com',
  'icloud.com',
  'aol.com',
  'mail.com',
  'protonmail.com',
  'zoho.com',
];

export default function Register() {
  const navigate = useNavigate();
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const [campuses, setCampuses] = useState([]);
  const [campusesLoaded, setCampusesLoaded] = useState(false);
  const [detectedCampus, setDetectedCampus] = useState(null);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  // Fetch approved campuses from Supabase as source of truth
  useEffect(() => {
    async function loadCampuses() {
      try {
        const { data, error } = await supabase
          .from('campuses')
          .select('campus_id, name, domain');
        if (!error && Array.isArray(data)) {
          setCampuses(data);
        }
      } catch (err) {
        console.warn('Could not load campus list for client-side hint:', err);
      } finally {
        setCampusesLoaded(true);
      }
    }
    loadCampuses();
  }, []);

  // Update detected campus when email changes
  useEffect(() => {
    if (!email || !email.includes('@')) {
      setDetectedCampus(null);
      return;
    }
    const domain = email.split('@')[1]?.toLowerCase().trim();
    if (campuses.length > 0) {
      const match = campuses.find((c) => c.domain?.toLowerCase() === domain);
      setDetectedCampus(match || null);
    } else {
      setDetectedCampus(null);
    }
  }, [email, campuses]);

  const validate = () => {
    if (!fullName.trim()) return 'Full name is required.';
    if (!email.trim()) return 'Institutional email is required.';

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) return 'Please enter a valid email address.';

    const domain = email.split('@')[1]?.toLowerCase().trim();

    // Check for public consumer email domains
    if (PUBLIC_EMAIL_DOMAINS.includes(domain)) {
      return 'Rentora is campus-exclusive. Generic consumer email addresses (Gmail, Yahoo, Outlook, etc.) are not permitted. Please use your institutional email.';
    }

    // Check against registered campuses if available
    if (campuses.length > 0) {
      const isApprovedDomain = campuses.some((c) => c.domain?.toLowerCase() === domain);
      const isInstitutionalTld =
        domain.endsWith('.edu') || domain.endsWith('.ac.uk') || domain.endsWith('.edu.in');

      if (!isApprovedDomain && !isInstitutionalTld) {
        return `Domain "@${domain}" is not an authorized campus domain. Only recognized campus domains or institutional addresses (.edu, .ac.uk, .edu.in) are accepted.`;
      }
    } else {
      // Fallback domain suffix check when campuses table is empty
      const isInstitutionalTld =
        domain.endsWith('.edu') || domain.endsWith('.ac.uk') || domain.endsWith('.edu.in');
      if (!isInstitutionalTld) {
        return `Domain "@${domain}" must be an institutional domain ending in .edu, .ac.uk, or .edu.in.`;
      }
    }

    if (!password) return 'Password is required.';
    if (password.length < 6) return 'Password must be at least 6 characters.';
    if (password !== confirmPassword) return 'Passwords do not match.';

    return null;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setInfo('');

    const validationError = validate();
    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);

    try {
      const domain = email.split('@')[1]?.toLowerCase().trim();
      const matched = campuses.find((c) => c.domain?.toLowerCase() === domain);

      const { data, error: supabaseError } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: {
          data: {
            full_name: fullName.trim(),
            campus_id: matched ? matched.campus_id : null,
          },
          emailRedirectTo: `${window.location.origin}/verify`,
        },
      });

      if (supabaseError) {
        setError(supabaseError.message);
      } else {
        setInfo(
          'Registration initiated! A verification link has been sent to your institutional email.'
        );
        setTimeout(() => {
          navigate('/verify');
        }, 1500);
      }
    } catch (err) {
      setError(err.message || 'An unexpected error occurred during registration.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Container maxWidth="sm" sx={{ py: 6 }}>
      <Paper elevation={3} sx={{ p: { xs: 3, sm: 4 } }}>
        <Box textAlign="center" mb={3}>
          <Typography variant="h4" color="primary" gutterBottom>
            Create Your Account
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Join Rentora to buy, rent, and swap academic gear within your campus community.
          </Typography>
        </Box>

        {error && (
          <Alert severity="error" sx={{ mb: 3 }}>
            {error}
          </Alert>
        )}
        {info && (
          <Alert severity="success" sx={{ mb: 3 }}>
            {info}
          </Alert>
        )}

        <Box component="form" onSubmit={handleSubmit} noValidate>
          <TextField
            label="Full Name"
            fullWidth
            margin="normal"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            required
            autoComplete="name"
          />

          <TextField
            label="Institutional Email"
            type="email"
            fullWidth
            margin="normal"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="student@university.edu"
            helperText="Must match an authorized campus domain (.edu, .ac.uk, .edu.in)"
            required
            autoComplete="email"
          />

          {detectedCampus && (
            <Box mt={1} mb={1}>
              <Chip
                label={`Detected Campus: ${detectedCampus.name}`}
                color="secondary"
                size="small"
              />
            </Box>
          )}

          <TextField
            label="Password"
            type={showPassword ? 'text' : 'password'}
            fullWidth
            margin="normal"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            helperText="Minimum 6 characters"
            required
            autoComplete="new-password"
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
            label="Confirm Password"
            type={showPassword ? 'text' : 'password'}
            fullWidth
            margin="normal"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            required
            autoComplete="new-password"
          />

          <Typography
            variant="caption"
            color="text.secondary"
            sx={{ display: 'block', mt: 1.5 }}
          >
            * Note: Frontend validation is provided for user convenience. Institutional verification
            and campus mapping are enforced on the server.
          </Typography>

          <Button
            type="submit"
            variant="contained"
            color="primary"
            fullWidth
            size="large"
            disabled={loading}
            sx={{ mt: 3, py: 1.2 }}
          >
            {loading ? <CircularProgress size={26} color="inherit" /> : 'Register'}
          </Button>

          <Box mt={3} textAlign="center">
            <Typography variant="body2">
              Already have an account?{' '}
              <Link to="/login" style={{ color: '#1E3A8A', fontWeight: 600 }}>
                Log in
              </Link>
            </Typography>
          </Box>
        </Box>
      </Paper>
    </Container>
  );
}
