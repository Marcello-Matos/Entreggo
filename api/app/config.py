from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://entreggo:entreggo@localhost:5432/entreggo"
    firebase_project_id: str = ""
    google_maps_api_key: str = ""
    nominatim_url: str = "https://nominatim.openstreetmap.org/search"
    nominatim_contact: str = ""
    max_import_bytes: int = 5_000_000
    max_import_rows: int = 2_000
    optimizer_time_limit_s: int = 5
    average_speed_kmh: float = 25.0
    pro_emails: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
