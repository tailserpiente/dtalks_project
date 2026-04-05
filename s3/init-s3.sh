#!/bin/bash

# Создание bucket в MinIO
sleep 5
mc alias set myminio http://minio:9000 ${MINIO_ROOT_USER:-minioadmin} ${MINIO_ROOT_PASSWORD:-minioadmin123}
mc mb myminio/github-archive --ignore-existing
mc policy set download myminio/github-archive

echo "S3 bucket 'github-archive' created"
