#!/usr/bin/env python3
import os
import boto3
import requests
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

S3_ENDPOINT = os.getenv('S3_ENDPOINT', 'http://localhost:9000')
S3_ACCESS_KEY = os.getenv('S3_ACCESS_KEY', 'minioadmin')
S3_SECRET_KEY = os.getenv('S3_SECRET_KEY', 'minioadmin123')
BUCKET_NAME = 'github-archive'
YEAR = 2015
MONTH = 1
DAY = 1

def setup_s3_client():
    return boto3.client(
        's3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        verify=False
    )

def download_and_upload(hour):
    url = f'https://data.gharchive.org/{YEAR}-{MONTH:02d}-{DAY:02d}-{hour}.json.gz'
    local_file = f'/tmp/github-{YEAR}-{MONTH:02d}-{DAY:02d}-{hour}.json.gz'
    s3_key = f'{YEAR}/{MONTH:02d}/{DAY:02d}/github-{YEAR}-{MONTH:02d}-{DAY:02d}-{hour}.json.gz'
    
    try:
        print(f"Downloading {url}...")
        response = requests.get(url, stream=True, timeout=30)
        response.raise_for_status()
        
        with open(local_file, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"Uploading to S3: {s3_key}")
        s3 = setup_s3_client()
        s3.upload_file(local_file, BUCKET_NAME, s3_key)
        
        os.remove(local_file)
        print(f"✓ Completed for hour {hour}")
        return True
    except Exception as e:
        print(f"✗ Failed for hour {hour}: {str(e)}")
        return False

def main():
    # Создаем bucket если не существует
    s3 = setup_s3_client()
    try:
        s3.head_bucket(Bucket=BUCKET_NAME)
    except:
        s3.create_bucket(Bucket=BUCKET_NAME)
    
    # Параллельная загрузка 24 часов
    hours = range(24)
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = {executor.submit(download_and_upload, hour): hour for hour in hours}
        
        for future in as_completed(futures):
            hour = futures[future]
            try:
                future.result()
            except Exception as e:
                print(f"Error for hour {hour}: {e}")

if __name__ == '__main__':
    main()
