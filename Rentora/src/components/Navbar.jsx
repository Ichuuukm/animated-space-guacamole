import React from 'react';
import { AppBar, Toolbar, Typography, Button, Box, Chip } from '@mui/material';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Navbar() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();

  const handleLogout = async () => {
    await signOut();
    navigate('/login');
  };

  return (
    <AppBar position="static" color="primary" elevation={1}>
      <Toolbar>
        <Typography
          variant="h6"
          component={Link}
          to="/"
          sx={{
            flexGrow: 1,
            textDecoration: 'none',
            color: 'inherit',
            fontWeight: 700,
            letterSpacing: 0.5,
          }}
        >
          🎓 Rentora
        </Typography>

        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          {user ? (
            <>
              <Chip
                label={user.email}
                size="small"
                sx={{
                  backgroundColor: 'rgba(255, 255, 255, 0.15)',
                  color: '#fff',
                  fontWeight: 500,
                  maxWidth: { xs: 140, sm: 220 },
                }}
              />
              <Button color="inherit" component={Link} to="/dashboard">
                Dashboard
              </Button>
              <Button color="inherit" onClick={handleLogout} variant="outlined" size="small">
                Logout
              </Button>
            </>
          ) : (
            <>
              <Button color="inherit" component={Link} to="/login">
                Login
              </Button>
              <Button
                component={Link}
                to="/register"
                variant="contained"
                sx={{
                  backgroundColor: 'secondary.main',
                  '&:hover': { backgroundColor: 'secondary.dark' },
                }}
                size="small"
              >
                Register
              </Button>
            </>
          )}
        </Box>
      </Toolbar>
    </AppBar>
  );
}
