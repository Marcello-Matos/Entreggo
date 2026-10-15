import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

RouteStatus = Literal["draft", "validated", "optimized", "in_progress", "completed", "archived"]
PackageStatus = Literal["pending", "delivered", "failed_attempt", "skipped"]
AddressStatus = Literal["pending_review", "ready", "not_found"]


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class RouteCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    start_address: str | None = Field(default=None, max_length=300)
    start_lat: float | None = Field(default=None, ge=-90, le=90)
    start_lng: float | None = Field(default=None, ge=-180, le=180)
    planned_at: datetime | None = None


class RouteUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)


class PackageCreate(BaseModel):
    tracking_code: str | None = Field(default=None, max_length=120)
    address_text: str | None = None
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, max_length=2)
    postal_code: str | None = Field(default=None, max_length=9)
    recipient_reference: str | None = Field(default=None, max_length=120)
    delivery_notes: str | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


class PackageUpdate(BaseModel):
    address_text: str | None = None
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, max_length=2)
    postal_code: str | None = Field(default=None, max_length=9)
    delivery_notes: str | None = None


class ScanIn(BaseModel):
    code: str = Field(min_length=1, max_length=120)


class PackageOut(ORMModel):
    id: uuid.UUID
    tracking_code: str | None
    address_text: str | None
    city: str | None
    state: str | None
    postal_code: str | None
    recipient_reference: str | None
    delivery_notes: str | None
    lat: float | None
    lng: float | None
    address_status: AddressStatus
    status: PackageStatus
    scanned_at: datetime | None = None
    recipient_name: str | None = None
    delivery_method: str | None = None
    delivered_at: datetime | None = None
    has_proof_photo: bool = False
    vehicle_location: str | None = None


class StopOut(ORMModel):
    package_id: uuid.UUID
    sequence: int
    eta_estimate: datetime | None


class RouteOut(ORMModel):
    id: uuid.UUID
    title: str
    start_address: str | None
    start_lat: float | None
    start_lng: float | None
    status: RouteStatus
    planned_at: datetime | None
    created_at: datetime
    total_packages: int = 0
    delivered_packages: int = 0
    pending_packages: int = 0


class ActiveRoute(BaseModel):
    id: uuid.UUID
    title: str
    remaining: int
    optimized: bool
    next_address: str | None = None
    next_eta: datetime | None = None
    next_lat: float | None = None
    next_lng: float | None = None
    remaining_seconds: int | None = None


class DashboardOut(BaseModel):
    packages: int
    delivered: int
    failed: int
    skipped: int
    pending: int
    progress: float
    active_route: ActiveRoute | None


class RouteDetail(RouteOut):
    packages: list[PackageOut]
    stops: list[StopOut]
    optimization: dict | None


class LocationUpdate(BaseModel):
    location: str | None = Field(default=None, max_length=60)


class LocationAssignment(BaseModel):
    package_id: uuid.UUID
    location: str | None = Field(default=None, max_length=60)


class BulkLocationUpdate(BaseModel):
    assignments: list[LocationAssignment] = Field(max_length=300)


class StatusUpdate(BaseModel):
    status: PackageStatus
    note: str | None = Field(default=None, max_length=500)
    recipient_name: str | None = Field(default=None, max_length=120)
    delivery_method: str | None = Field(default=None, max_length=30)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


class GeocodeResult(BaseModel):
    geocoded: int
    not_found: int
    pending: int
    start_found: bool


class OptimizeIn(BaseModel):
    objective: Literal["distance"] = "distance"
    start_lat: float | None = Field(default=None, ge=-90, le=90)
    start_lng: float | None = Field(default=None, ge=-180, le=180)
    start_address: str | None = Field(default=None, max_length=300)


class OptimizeOut(BaseModel):
    stops: list[StopOut]
    total_distance_m: int
    estimated_duration_s: int
    skipped_package_ids: list[uuid.UUID]
    provider: str
    objective: str
    disclaimer: str


class ImportJobOut(ORMModel):
    id: uuid.UUID
    route_id: uuid.UUID
    filename: str
    status: str
    error_summary: dict | None


class RouteSummary(BaseModel):
    route_id: uuid.UUID
    status: RouteStatus
    total: int
    by_status: dict[str, int]
    pending_address_review: int
    total_distance_m: int | None


class SubscriptionOut(BaseModel):
    entitlement: str
    product_id: str | None
    expires_at: datetime | None
    source: str
    limits: dict[str, int]


class PlayPurchaseIn(BaseModel):
    product_id: str = Field(min_length=1, max_length=120)
    purchase_token: str = Field(min_length=1, max_length=512)
