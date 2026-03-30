import os
import logging
from flask import Flask, request, jsonify

app = Flask(__name__)

LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
PORT = int(os.environ.get('PORT', '5000'))
WELCOME_TITLE = os.environ.get('WELCOME_TITLE', 'Welcome to the custom app')
LOG_FILE = '/app/logs/app.log'

os.makedirs('/app/logs', exist_ok=True)

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


@app.route('/')
def index():
    logger.info('GET /')
    return WELCOME_TITLE


@app.route('/status')
def status():
    logger.info('GET /status')
    return jsonify({'status': 'ok'})


@app.route('/log', methods=['POST'])
def log():
    data = request.get_json(silent=True)
    if not data or 'message' not in data:
        return jsonify({'error': 'Missing message field'}), 400
    message = data['message']
    logger.info('POST /log: %s', message)
    with open(LOG_FILE, 'a') as f:
        f.write(f'{message}\n')
    return jsonify({'status': 'logged', 'message': message})


@app.route('/logs')
def logs():
    logger.info('GET /logs')
    try:
        with open(LOG_FILE, 'r') as f:
            content = f.read()
        return content, 200, {'Content-Type': 'text/plain'}
    except FileNotFoundError:
        return '', 200, {'Content-Type': 'text/plain'}


if __name__ == '__main__':
    logger.info('Starting app on port %d', PORT)
    app.run(host='0.0.0.0', port=PORT)
