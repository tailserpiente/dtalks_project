# dtalks_project
FInal datatalks project

github_analytics/
├── docker-compose.yml
├── .env
├── s3/
│   └── init-s3.sh
├── postgres/
│   └── init-datavault.sql
├── dbt/
│   ├── Dockerfile
│   ├── profiles.yml
│   ├── dbt_project.yml
│   ├── models/
│   │   ├── raw/
│   │   ├── datavault/
│   │   └── marts/
│   └── macros/
├── clickhouse/
│   └── init.sql
├── superset/
│   └── superset_config.py
├── scripts/
│   ├── download_to_s3.py
│   ├── load_to_postgres.py
│   └── run_dbt.py
└── requirements.txt

#run all containers
docker compose up -d

#stop all containers
docker compose down 

# Войдите в контейнер minio
docker exec -it minio sh

# Установите mc (minio client)
curl -o mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin/

# Настройте подключение
mc alias set myminio http://localhost:9000 minioadmin minioadmin123

# Создайте bucket
mc mb myminio/github-archive

# Выйдите
exit

docker exec -it minio sh
sh-5.1# apk add mc
sh: apk: command not found
sh-5.1# wget https://dl.min.io/client/mc/release/linux-amd64/mc
sh: wget: command not found
sh-5.1# curl -o mc https://dl.min.io/client/mc/release/linux-amd64/mc
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 29.1M  100 29.1M    0     0  7098k      0  0:00:04  0:00:04 --:--:-- 7100k
sh-5.1# chmod +x mc
mv mc /usr/local/bin/
sh-5.1# mc alias set myminio http://localhost:9000 minioadmin minioadmin123
mc: Configuration written to `/tmp/.mc/config.json`. Please update your access credentials.
mc: Successfully created `/tmp/.mc/share`.
mc: Initialized share uploads `/tmp/.mc/share/uploads.json` file.
mc: Initialized share downloads `/tmp/.mc/share/downloads.json` file.
Added `myminio` successfully.
sh-5.1# mc mb myminio/github-archive
Bucket created successfully `myminio/github-archive`.
sh-5.1# exit

#step 1. set local wsl minio client. Download files to the host wsl system (due to unable using proxy from dbt container)

wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
mc alias set myminio http://localhost:9000 minioadmin minioadmin123


cd github_files
for i in {0..23}; do
    echo "Downloading hour $i..."
    wget https://data.gharchive.org/2015-01-01-$i.json.gz
done

for i in {0..23}; do
    echo "Uploading hour $i..."
    mc cp 2015-01-01-$i.json.gz myminio/github-archive/2015/01/01/
done


#install some data into dbt container 
docker compose exec dbt bash
pip install --root-user-action=ignore boto3 requests psycopg2-binary clickhouse-driver
pip install boto3 requests psycopg2-binary clickhouse-driver 2>/dev/null

#step 2 - load from mc to postgres.RAW 

python3 /scripts/load_to_postgres.py 

python /scripts/run_dbt.py



