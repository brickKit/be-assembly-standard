FROM python:3.12-slim
# git：pip 要 clone besdk 的 git+https 依赖；wget：平台健康检查是 CMD-SHELL + wget
RUN apt-get update && apt-get install -y --no-install-recommends wget git ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY pyproject.toml main.py ./
RUN pip install --no-cache-dir .
COPY . .
ENTRYPOINT ["python", "main.py"]
