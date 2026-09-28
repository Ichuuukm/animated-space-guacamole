// src/pages/Dashboard.jsx
import React from 'react';
import {
  Container,
  Paper,
  Typography,
  Box,
  Button,
  Grid,
  Card,
  CardContent,
  Chip,
} from '@mui/material';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';

export default function Dashboard() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();

  const handleLogout = async () => {
    await signOut();
    navigate('/login');
  };

  const fullName = user?.user_metadata?.full_name || 'Student';
  const email = user?.email || '';

  return (
    <Container maxWidth="md" sx={{ py: 6 }}>
      <Paper elevation={2} sx={{ p: 4, mb: 4, borderRadius: 3 }}>
        <Box display="flex" justifyContent="space-between" alignItems="center" flexWrap="wrap" gap={2}>
          <Box>
            <Typography variant="h4" color="primary" gutterBottom>
              Welcome back, {fullName}! 👋
            </Typography>
            <Typography variant="body1" color="text.secondary">
              Campus Member: <strong>{email}</strong>
            </Typography>
          </Box>
          <Box display="flex" gap={1.5} alignItems="center">
            <Chip
              label="Institutional Email Verified"
              color="success"
              variant="outlined"
              size="medium"
            />
            <Button variant="outlined" color="primary" onClick={handleLogout}>
              Log Out
            </Button>
          </Box>
        </Box>
      </Paper>

      <Typography variant="h5" sx={{ mb: 2, fontWeight: 600 }}>
        Rentora Marketplace
      </Typography>

      <Grid container spacing={3}>
        <Grid item xs={12} sm={4}>
          <Card sx={{ height: '100%', borderTop: '4px solid #1E40AF' }}>
            <CardContent>
              <Chip label="Rent" color="primary" size="small" sx={{ mb: 1.5 }} />
              <Typography variant="h6" gutterBottom>
                Borrow Academic Gear
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Rent calculators, lab equipment, cameras, and textbooks by the day or semester.
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={4}>
          <Card sx={{ height: '100%', borderTop: '4px solid #16A34A' }}>
            <CardContent>
              <Chip label="Buy" color="success" size="small" sx={{ mb: 1.5 }} />
              <Typography variant="h6" gutterBottom>
                Buy Second-Hand
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Save money on course materials and gear directly from students on your campus.
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={4}>
          <Card sx={{ height: '100%', borderTop: '4px solid #9333EA' }}>
            <CardContent>
              <Chip
                label="Swap"
                size="small"
                sx={{ mb: 1.5, backgroundColor: '#9333EA', color: '#fff' }}
              />
              <Typography variant="h6" gutterBottom>
                Swap Course Textbooks
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Trade books with peers across department and course codes with zero cash friction.
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Container>
  );
}
