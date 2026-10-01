from app import app, init_db

bind = "0.0.0.0:5000"
workers = 2
accesslog = "-"
errorlog = "-"


def on_starting(server):
    with app.app_context():
        init_db()
