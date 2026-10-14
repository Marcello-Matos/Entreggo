# Assinaturas (magic bytes) dos formatos que o app consegue exibir.
# Fotos do iPhone costumam chegar como HEIC ou com tipo "octet-stream",
# então o formato é detectado pelo conteúdo, não pelo Content-Type declarado.
_HEIC_BRANDS = {
    b"heic",
    b"heix",
    b"hevc",
    b"hevx",
    b"heim",
    b"heis",
    b"mif1",
    b"msf1",
}


def detect_image_type(data: bytes) -> str | None:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if data[:2] == b"BM":
        return "image/bmp"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        if data[8:12] in _HEIC_BRANDS:
            return "image/heic"
        if data[8:12] == b"avif":
            return "image/avif"
    return None
