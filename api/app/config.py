from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://entreggo:entreggo@localhost:5432/entreggo"
    supabase_url: str = ""
    supabase_jwt_secret: str = ""
    jwt_audience: str = "authenticated"
    google_maps_api_key: str = ""
    max_import_bytes: int = 5_000_000
    max_import_rows: int = 2_000
    optimizer_time_limit_s: int = 5
    average_speed_kmh: float = 25.0


@lru_cache
def get_settings() -> Settings:
    return Settings()
