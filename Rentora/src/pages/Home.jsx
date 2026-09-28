// src/pages/Home.jsx
import React from 'react';
import {
  Container,
  Typography,
  Button,
  Box,
  Grid,
  Card,
  CardContent,
  Chip,
  Paper,
} from '@mui/material';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Home() {
  const { user } = useAuth();

  return (
    <Container maxWidth="md" sx={{ py: 8 }}>
      <Paper
        elevation={0}
        sx={{
          p: { xs: 4, sm: 6 },
          textAlign: 'center',
          backgroundColor: '#FFFFFF',
          borderRadius: 4,
          border: '1px solid #E2E8F0',
          mb: 6,
        }}
      >
        <Typography
          variant="h3"
          component="h1"
          sx={{ fontWeight: 800, color: 'primary.main', mb: 2 }}
        >
          Rentora
        </Typography>
        <Typography variant="h5" color="text.secondary" sx={{ mb: 3, fontWeight: 500 }}>
          Campus-Exclusive Peer-to-Peer Marketplace
        </Typography>
        <Typography
          variant="body1"
          color="text.secondary"
          sx={{ maxWidth: 600, mx: 'auto', mb: 4 }}
        >
          Buy, rent, and swap academic gear, lab tools, and textbooks exclusively with verified
          students on your campus.
        </Typography>

        <Box display="flex" justifyContent="center" gap={2} flexWrap="wrap">
          {user ? (
            <Button
              component={Link}
              to="/dashboard"
              variant="contained"
              color="primary"
              size="large"
              sx={{ px: 4, py: 1.2 }}
            >
              Go to Campus Dashboard
            </Button>
          ) : (
            <>
              <Button
                component={Link}
                to="/register"
                variant="contained"
                color="primary"
                size="large"
                sx={{ px: 4, py: 1.2 }}
              >
                Join with Campus Email
              </Button>
              <Button
                component={Link}
                to="/login"
                variant="outlined"
                color="primary"
                size="large"
                sx={{ px: 4, py: 1.2 }}
              >
                Sign In
              </Button>
            </>
          )}
        </Box>
      </Paper>

      {/* Feature Badges from Rentora Rules */}
      <Grid container spacing={3}>
        <Grid item xs={12} sm={4}>
          <Card elevation={1} sx={{ height: '100%', borderRadius: 3 }}>
            <CardContent>
              <Chip label="Rent ($/day)" color="primary" size="small" sx={{ mb: 1.5 }} />
              <Typography variant="h6" gutterBottom>
                Peer-to-Peer Rentals
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Affordable daily and weekly rates on graphing calculators, lab gear, and tech.
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={4}>
          <Card elevation={1} sx={{ height: '100%', borderRadius: 3 }}>
            <CardContent>
              <Chip label="Buy ($)" color="success" size="small" sx={{ mb: 1.5 }} />
              <Typography variant="h6" gutterBottom>
                Verified Student Sales
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Skip retail markups. Purchase textbooks and materials directly from upperclassmen.
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={4}>
          <Card elevation={1} sx={{ height: '100%', borderRadius: 3 }}>
            <CardContent>
              <Chip
                label="Swap (Open to Trade)"
                size="small"
                sx={{ mb: 1.5, backgroundColor: '#9333EA', color: '#fff' }}
              />
              <Typography variant="h6" gutterBottom>
                Direct Course Swaps
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Trade required reading and textbooks across departments and courses for zero cost.
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Container>
  );
}
