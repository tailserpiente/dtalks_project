#!/usr/bin/env python3
import os
import boto3
import psycopg2
import gzip
import json
from psycopg2.extras import execute_batch

S3_ENDPOINT = os.getenv('S3_ENDPOINT', 'http://minio:9000')
BUCKET_NAME = 'github-archive'
POSTGRES_HOST = os.getenv('POSTGRES_HOST', 'postgres')
POSTGRES_USER = os.getenv('POSTGRES_USER', 'analytics_user')
POSTGRES_PASSWORD = os.getenv('POSTGRES_PASSWORD', 'analytics_pass')
POSTGRES_DB = os.getenv('POSTGRES_DB', 'github_analytics')

def clean_string(s):
    """Remove null bytes and other problematic characters"""
    if s is None:
        return None
    if isinstance(s, str):
        return s.replace('\u0000', '').replace('\x00', '')
    return s

def clean_json(obj):
    """Recursively clean JSON object"""
    if isinstance(obj, dict):
        return {k: clean_json(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [clean_json(item) for item in obj]
    elif isinstance(obj, str):
        return clean_string(obj)
    else:
        return obj

def get_s3_client():
    return boto3.client(
        's3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=os.getenv('S3_ACCESS_KEY', 'minioadmin'),
        aws_secret_access_key=os.getenv('S3_SECRET_KEY', 'minioadmin123'),
        verify=False
    )

def load_events_to_postgres(date_str: str = '2015-01-01'):
    year, month, day = date_str.split('-')
    s3_prefix = f'{year}/{month}/{day}/'

    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        database=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD
    )
    cursor = conn.cursor()

    s3 = get_s3_client()

    response = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=s3_prefix)
    
    for obj in response.get('Contents', []):
        print(f"Processing {obj['Key']}")
        
        s3.download_file(BUCKET_NAME, obj['Key'], '/tmp/temp.gz')
        
        events = []
        error_count = 0
        
        with gzip.open('/tmp/temp.gz', 'rt', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    # Очищаем строку от null bytes
                    line = line.replace('\u0000', '').replace('\x00', '')
                    
                    if not line.strip():
                        continue
                    
                    data = json.loads(line)
                    
                    # Очищаем данные от null bytes
                    data = clean_json(data)
                    
                    event = {
                        'id': data.get('id'),
                        'event_type': data.get('type'),
                        'actor_id': data.get('actor', {}).get('id'),
                        'actor_login': clean_string(data.get('actor', {}).get('login')),
                        'repo_id': data.get('repo', {}).get('id'),
                        'repo_name': clean_string(data.get('repo', {}).get('name')),
                        'created_at': data.get('created_at'),
                        'payload': json.dumps(data.get('payload', {})),
                        'raw_data': json.dumps(data)
                    }
                    events.append(event)
                    
                except json.JSONDecodeError as e:
                    error_count += 1
                    if error_count <= 5:
                        print(f"  JSON error line {line_num}: {e}")
                    continue
                except Exception as e:
                    error_count += 1
                    if error_count <= 5:
                        print(f"  Error line {line_num}: {e}")
                    continue
        
        if events:
            insert_sql = """
                INSERT INTO raw.github_events 
                (id, event_type, actor_id, actor_login, repo_id, repo_name, created_at, payload, raw_data)
                VALUES (%(id)s, %(event_type)s, %(actor_id)s, %(actor_login)s, 
                        %(repo_id)s, %(repo_name)s, %(created_at)s, %(payload)s, %(raw_data)s)
                ON CONFLICT (id) DO NOTHING
            """
            
            # Вставляем порциями по 500 записей
            for i in range(0, len(events), 500):
                batch = events[i:i+500]
                execute_batch(cursor, insert_sql, batch, page_size=500)
                conn.commit()
                print(f"  ✓ Inserted {len(batch)} events (total {len(events)})")
        
        print(f"✓ Completed {obj['Key']}: {len(events)} events, {error_count} errors")
        os.remove('/tmp/temp.gz')
    
    cursor.close()
    conn.close()
    print("\n✅ All data loaded successfully!")

if __name__ == '__main__':
    import sys
    date_arg = sys.argv[1] if len(sys.argv) > 1 else '2015-01-01'
    load_events_to_postgres(date_arg)