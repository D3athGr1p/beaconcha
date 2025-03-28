import psycopg2
from psycopg2 import sql
import os
from dotenv import load_dotenv
from google.cloud import bigtable
import redis
import subprocess

load_dotenv()


def get_container_ip(container_name):
    try:
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", container_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        # Capture the IP from the output
        ip_address = result.stdout.strip()
        if result.returncode != 0 or not ip_address:
            raise Exception(f"Error fetching IP for container: {container_name}")
        return ip_address
    except Exception as e:
        print(f"Error: {e}")
        return None

DB_HOST = get_container_ip("eth2-beaconchain-explorer-postgres-1")
REDIS_HOST = get_container_ip("eth2-beaconchain-explorer-redis-1")
EMULATOR_HOST = get_container_ip("eth2-beaconchain-explorer-lbt-1")

# PostgreSQL Configuration
DB_USER = os.getenv("DB_USER", "user")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_PASSWORD = os.getenv("DB_PASSWORD", "pass")
DB_NAME = os.getenv("DB_NAME", "db")

# Redis Configuration
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
REDIS_DB = os.getenv("REDIS_DB", "0")

# Bigtable Configuration
PROJECT_ID = "explorer"
INSTANCE_ID = f"{EMULATOR_HOST}:9000"
EMULATOR_PORT = "9000"
os.environ["BIGTABLE_EMULATOR_HOST"] = f"{EMULATOR_HOST}:{EMULATOR_PORT}"
BIGTABLE_TABLES = ['blocks', 'data', 'machine_metrics', 'metadata', 'metadata_updates', 'beaconchain_validators', 'beaconchain_validators_history']


# Function for PostgreSQL Operations
def create_pg_connection():
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT
        )
        return conn
    except Exception as e:
        print(f"Error: Unable to connect to the PostgreSQL database. {e}")
        return None


def list_pg_tables(conn):
    table_names = []
    try:
        with conn.cursor() as cur:
            query = """
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public';
            """
            cur.execute(query)
            tables = cur.fetchall()
            print("Tables in PostgreSQL database:")
            for table in tables:
                table_name = table[0]
                table_names.append(table_name)
                print(table_name)
    except Exception as e:
        print(f"Error: {e}")
    
    return table_names


def list_pg_data(conn, table_names):
    try:
        with conn.cursor() as cur:
            for table_name in table_names:
                print(f"\nData from table: {table_name}")
                query = sql.SQL("SELECT * FROM {}").format(sql.Identifier(table_name))
                cur.execute(query)
                rows = cur.fetchall()
                for row in rows:
                    print(row)
    except Exception as e:
        print(f"Error: {e}")


def delete_pg_table_data(conn, table_name):
    try:
        with conn.cursor() as cur:
            query = sql.SQL("DELETE FROM {}").format(sql.Identifier(table_name))
            cur.execute(query)
            conn.commit()
            print(f"All data deleted from PostgreSQL table: {table_name}")
    except Exception as e:
        print(f"Error: {e}")


# Function for Bigtable Operations
def list_bigtable_rows():
    client = bigtable.Client(project=PROJECT_ID, admin=True)
    instance = client.instance(INSTANCE_ID)

    for table_id in BIGTABLE_TABLES:
        table = instance.table(table_id)
        print(f"\nListing rows from Bigtable table '{table_id}':")
        rows = table.read_rows()
        for row in rows:
            print(f"Row key: {row.row_key}, Data: {row.cells}")

# Function for Redis Operations
def create_redis_connection():
    try:
        client = redis.StrictRedis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=False)
        return client
    except Exception as e:
        print(f"Error: Unable to connect to Redis. {e}")
        return None


def list_redis_keys(client):
    try:
        keys = client.keys('*')
        print("\nKeys in Redis:")
        for key in keys:
            print(key)
        return keys
    except Exception as e:
        print(f"Error: {e}")
        return []


def list_redis_data(client, keys):
    try:
        for key in keys:
            print(f"\nData for key: {key}")
            data = client.get(key)
            if isinstance(data, bytes):
                print(f"Binary data: {data}")
            else:
                print(f"String data: {data}")
    except Exception as e:
        print(f"Error: {e}")


def delete_redis_key_data(client, key):
    try:
        client.delete(key)
        print(f"Data deleted for key: {key}")
    except Exception as e:
        print(f"Error: {e}")


# User-Friendly Menu System
def menu():
    print("\nSelect an option:")
    print("1. PostgreSQL Operations")
    print("2. Bigtable Operations")
    print("3. Redis Operations")
    print("4. Exit")

    choice = input("Enter choice (1-4): ")
    return choice


def pg_operations():
    conn = create_pg_connection()
    if conn:
        print("\n1. List Tables")
        print("2. List Data")
        print("3. Delete Data from Table")
        pg_choice = input("Enter choice (1-3): ")

        if pg_choice == '1':
            tables = list_pg_tables(conn)
        elif pg_choice == '2':
            tables = list_pg_tables(conn)
            list_pg_data(conn, tables)
        elif pg_choice == '3':
            table = input("Enter table name to delete data from: ")
            delete_pg_table_data(conn, table)
        conn.close()


def bigtable_operations():
    print("\nListing rows from Bigtable...")
    
    list_bigtable_rows()


def redis_operations():
    client = create_redis_connection()
    if client:
        print("\n1. List Keys")
        print("2. List Data for Keys")
        print("3. Delete Data for Key")
        redis_choice = input("Enter choice (1-3): ")

        if redis_choice == '1':
            list_redis_keys(client)
        elif redis_choice == '2':
            keys = list_redis_keys(client)
            list_redis_data(client, keys)
        elif redis_choice == '3':
            key = input("Enter key to delete data for: ")
            delete_redis_key_data(client, key)


def main():
    while True:
        choice = menu()
        if choice == '1':
            pg_operations()
        elif choice == '2':
            bigtable_operations()
        elif choice == '3':
            redis_operations()
        elif choice == '4':
            print("Exiting...")
            break
        else:
            print("Invalid choice. Please try again.")


if __name__ == "__main__":
    main()
