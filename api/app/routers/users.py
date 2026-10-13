from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User, UserPhoto

router = APIRouter(prefix="/v1/users", tags=["users"])

MAX_PHOTO_BYTES = 2 * 1024 * 1024
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}


@router.put("/me/photo", status_code=status.HTTP_204_NO_CONTENT)
async def upload_photo(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Grava a foto de perfil no banco (substitui a anterior, se houver)."""
    content = await file.read(MAX_PHOTO_BYTES + 1)
    if len(content) > MAX_PHOTO_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Foto muito grande (máx. 2 MB)"
        )
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Use uma imagem JPEG, PNG ou WebP"
        )
    photo = db.get(UserPhoto, user.id)
    if photo is None:
        db.add(UserPhoto(user_id=user.id, data=content, content_type=file.content_type))
    else:
        photo.data, photo.content_type = content, file.content_type
    db.commit()


@router.get("/me/photo")
def get_photo(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    photo = db.get(UserPhoto, user.id)
    if photo is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Sem foto de perfil")
    return Response(
        content=photo.data,
        media_type=photo.content_type,
        headers={"Cache-Control": "private, max-age=300"},
    )


@router.delete("/me/photo", status_code=status.HTTP_204_NO_CONTENT)
def delete_photo(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    photo = db.get(UserPhoto, user.id)
    if photo is not None:
        db.delete(photo)
        db.commit()
