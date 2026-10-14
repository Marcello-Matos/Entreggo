from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User, UserPhoto
from app.services.images import detect_image_type

router = APIRouter(prefix="/v1/users", tags=["users"])

MAX_PHOTO_BYTES = 5 * 1024 * 1024


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
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Foto muito grande (máx. 5 MB)"
        )
    media_type = detect_image_type(content)
    if media_type is None and (file.content_type or "").startswith("image/"):
        media_type = file.content_type
    if media_type is None:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            "Envie uma foto (JPEG, PNG, HEIC, WebP, GIF ou BMP)",
        )
    photo = db.get(UserPhoto, user.id)
    if photo is None:
        db.add(UserPhoto(user_id=user.id, data=content, content_type=media_type))
    else:
        photo.data, photo.content_type = content, media_type
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
