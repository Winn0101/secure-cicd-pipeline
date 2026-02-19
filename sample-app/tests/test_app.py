"""
Unit tests for sample application
"""

import unittest
import json
from src.app import app

class TestApp(unittest.TestCase):
    
    def setUp(self):
        """Set up test client"""
        self.app = app.test_client()
        self.app.testing = True
    
    def test_health_check(self):
        """Test health check endpoint"""
        response = self.app.get('/health')
        self.assertEqual(response.status_code, 200)
        
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')
        self.assertIn('timestamp', data)
        self.assertIn('version', data)
    
    def test_readiness_check(self):
        """Test readiness check endpoint"""
        response = self.app.get('/ready')
        self.assertEqual(response.status_code, 200)
        
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'ready')
    
    def test_index(self):
        """Test root endpoint"""
        response = self.app.get('/')
        self.assertEqual(response.status_code, 200)
        
        data = json.loads(response.data)
        self.assertIn('message', data)
        self.assertIn('version', data)
    
    def test_api_data(self):
        """Test API data endpoint"""
        response = self.app.get('/api/data')
        self.assertEqual(response.status_code, 200)
        
        data = json.loads(response.data)
        self.assertIn('data', data)
        self.assertIsInstance(data['data'], list)
        self.assertGreater(len(data['data']), 0)
    
    def test_404_handler(self):
        """Test 404 error handler"""
        response = self.app.get('/nonexistent')
        self.assertEqual(response.status_code, 404)
        
        data = json.loads(response.data)
        self.assertEqual(data['status'], 404)
    
    def test_security_headers(self):
        """Test security headers are present"""
        response = self.app.get('/')
        
        self.assertIn('X-Content-Type-Options', response.headers)
        self.assertEqual(response.headers['X-Content-Type-Options'], 'nosniff')
        
        self.assertIn('X-Frame-Options', response.headers)
        self.assertEqual(response.headers['X-Frame-Options'], 'DENY')
        
        self.assertIn('X-XSS-Protection', response.headers)

if __name__ == '__main__':
    unittest.main()
