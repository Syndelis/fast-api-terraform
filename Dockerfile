FROM python:3.11-slim-bookworm

RUN pip install pipenv

WORKDIR /api

COPY Pipfile Pipfile.lock ./
COPY src .

RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=bind,source=Pipfile,target=Pipfile \
    pipenv install --system --dev

ENTRYPOINT [ \
    "uvicorn", \
    "--app-dir", "src/", \
    "--host", "0.0.0.0", \
    "--port", "8000", \
    "--reload", \
    "main:api" \
]
