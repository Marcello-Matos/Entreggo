import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    JSON,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(UTC)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)  # uid do Firebase
    email: Mapped[str | None] = mapped_column(String(320))
    status: Mapped[str] = mapped_column(String(20), default="active")


class Route(TimestampMixin, Base):
    __tablename__ = "routes"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    start_address: Mapped[str | None] = mapped_column(Text)
    start_lat: Mapped[float | None] = mapped_column(Float)
    start_lng: Mapped[float | None] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(20), default="draft", index=True)
    planned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    optimization: Mapped[dict | None] = mapped_column(JSON)

    packages: Mapped[list["Package"]] = relationship(
        back_populates="route", cascade="all, delete-orphan", order_by="Package.created_at"
    )
    stops: Mapped[list["RouteStop"]] = relationship(
        back_populates="route", cascade="all, delete-orphan", order_by="RouteStop.sequence"
    )

    @property
    def total_packages(self) -> int:
        return len(self.packages)

    @property
    def delivered_packages(self) -> int:
        return sum(p.status == "delivered" for p in self.packages)

    @property
    def pending_packages(self) -> int:
        return sum(p.status == "pending" for p in self.packages)


class Package(TimestampMixin, Base):
    __tablename__ = "packages"
    __table_args__ = (UniqueConstraint("route_id", "tracking_code"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    route_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("routes.id", ondelete="CASCADE"), index=True
    )
    tracking_code: Mapped[str | None] = mapped_column(String(120), index=True)
    address_text: Mapped[str | None] = mapped_column(Text)
    city: Mapped[str | None] = mapped_column(String(120))
    state: Mapped[str | None] = mapped_column(String(2))
    postal_code: Mapped[str | None] = mapped_column(String(9))
    recipient_reference: Mapped[str | None] = mapped_column(String(120))
    delivery_notes: Mapped[str | None] = mapped_column(Text)
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    address_status: Mapped[str] = mapped_column(String(20), default="pending_review")
    geocode_meta: Mapped[dict | None] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(20), default="pending", index=True)
    scanned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Posição física no veículo ("Fundo • Meio • Prateleira") — v1.4+
    vehicle_location: Mapped[str | None] = mapped_column(String(60))

    route: Mapped[Route] = relationship(back_populates="packages")
    proof: Mapped["DeliveryProof | None"] = relationship(
        cascade="all, delete-orphan", single_parent=True
    )

    @property
    def recipient_name(self) -> str | None:
        return self.proof.recipient_name if self.proof else None

    @property
    def delivery_method(self) -> str | None:
        return self.proof.delivery_method if self.proof else None

    @property
    def delivered_at(self) -> datetime | None:
        return self.proof.created_at if self.proof else None

    @property
    def has_proof_photo(self) -> bool:
        return bool(self.proof and self.proof.photo)


class RouteStop(Base):
    __tablename__ = "route_stops"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    route_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("routes.id", ondelete="CASCADE"), index=True
    )
    package_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("packages.id", ondelete="CASCADE"))
    sequence: Mapped[int] = mapped_column(Integer)
    eta_estimate: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    route: Mapped[Route] = relationship(back_populates="stops")


class ImportJob(TimestampMixin, Base):
    __tablename__ = "import_jobs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    route_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("routes.id", ondelete="CASCADE"))
    filename: Mapped[str] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(20), default="processing")
    error_summary: Mapped[dict | None] = mapped_column(JSON)


class UserPhoto(Base):
    __tablename__ = "user_photos"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    data: Mapped[bytes] = mapped_column(LargeBinary)
    content_type: Mapped[str] = mapped_column(String(50))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class DeliveryProof(Base):
    """Comprovante de entrega/tentativa: foto no local, recebedor, GPS e horário."""

    __tablename__ = "delivery_proofs"

    package_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("packages.id", ondelete="CASCADE"), primary_key=True
    )
    recipient_name: Mapped[str | None] = mapped_column(String(120))
    # Como a entrega foi feita: assinatura, porteiro, vizinho... — v1.5+
    delivery_method: Mapped[str | None] = mapped_column(String(30))
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    photo: Mapped[bytes | None] = mapped_column(LargeBinary)
    photo_content_type: Mapped[str | None] = mapped_column(String(50))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class Subscription(Base):
    __tablename__ = "subscriptions"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    product_id: Mapped[str] = mapped_column(String(120))
    entitlement: Mapped[str] = mapped_column(String(40))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    source: Mapped[str] = mapped_column(String(40))


class DeliveryEvent(Base):
    __tablename__ = "delivery_events"
    __table_args__ = (Index("ix_delivery_events_package_ts", "package_id", "timestamp"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    package_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("packages.id", ondelete="CASCADE"))
    event_type: Mapped[str] = mapped_column(String(40))
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    note: Mapped[str | None] = mapped_column(Text)
