"""
Sample Flask Application
Demonstrates secure coding practices
"""

from flask import Flask, jsonify, request
import os
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Security headers
@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    return response

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'version': os.getenv('APP_VERSION', '1.0.0')
    }), 200

@app.route('/ready', methods=['GET'])
def readiness_check():
    """Readiness check endpoint"""
    # Add any readiness checks here (database connection, etc.)
    return jsonify({
        'status': 'ready',
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/', methods=['GET'])
def index():
    """Root endpoint"""
    return jsonify({
        'message': 'Secure CI/CD Pipeline Demo',
        'version': os.getenv('APP_VERSION', '1.0.0'),
        'environment': os.getenv('ENVIRONMENT', 'development')
    }), 200

@app.route('/api/data', methods=['GET'])
def get_data():
    """Sample API endpoint"""
    logger.info("Data endpoint accessed")
    
    return jsonify({
        'data': [
            {'id': 1, 'name': 'Item 1'},
            {'id': 2, 'name': 'Item 2'},
            {'id': 3, 'name': 'Item 3'}
        ],
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.errorhandler(404)
def not_found(error):
    """404 error handler"""
    return jsonify({
        'error': 'Not found',
        'status': 404
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """500 error handler"""
    logger.error(f"Internal error: {error}")
    return jsonify({
        'error': 'Internal server error',
        'status': 500
    }), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(
        host='0.0.0.0',
        port=port,
        debug=False  # Never run debug in production
    )
