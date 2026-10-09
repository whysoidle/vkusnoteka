FROM python:3.12-slim
WORKDIR /service
COPY backend /service/backend
RUN pip install --no-cache-dir -r backend/requirements.lock && pip install --no-cache-dir --no-deps ./backend
USER 65532:65532
EXPOSE 8000
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
