from fastapi import FastAPI
import psycopg2 as pg
import os

api = FastAPI()
conn = pg.connect(
    host=os.getenv("DATABASE_HOST"),
    port=os.getenv("DATABASE_PORT") or "5432",
    user="postgres",
    password="postgres"
)

@api.get("/")
def index():
    cursor = conn.cursor()
    cursor.execute("SELECT gen_random_uuid();")
    res, *_ = cursor.fetchone()
    return f"from db: {res}"
