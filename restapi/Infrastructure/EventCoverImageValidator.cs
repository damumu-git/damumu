namespace Muda.Api.Infrastructure;

public static class EventCoverImageValidator
{
    public static void Validate(IFormFile image)
    {
        if (image.Length is <= 0 or > 2_097_152)
            throw new ApiException(400, "cover_size_invalid", "活动图片不得超过 2 MB");
        if (!string.Equals(image.ContentType, "image/jpeg", StringComparison.OrdinalIgnoreCase))
            throw new ApiException(400, "cover_format_invalid", "活动图片仅支持 1280×960 JPEG");

        using var stream = image.OpenReadStream();
        using var reader = new BinaryReader(stream);
        if (ReadByte(reader) != 0xFF || ReadByte(reader) != 0xD8)
            throw InvalidImage();

        while (stream.Position < stream.Length)
        {
            if (ReadByte(reader) != 0xFF) continue;
            byte marker;
            do marker = ReadByte(reader); while (marker == 0xFF);
            if (marker is 0xD8 or 0xD9) continue;

            var segmentLength = ReadUInt16BigEndian(reader);
            if (segmentLength < 2) throw InvalidImage();
            if (marker is 0xC0 or 0xC1 or 0xC2 or 0xC3
                or 0xC5 or 0xC6 or 0xC7 or 0xC9 or 0xCA or 0xCB
                or 0xCD or 0xCE or 0xCF)
            {
                _ = ReadByte(reader);
                var height = ReadUInt16BigEndian(reader);
                var width = ReadUInt16BigEndian(reader);
                if (width != 1280 || height != 960)
                    throw new ApiException(
                        400, "cover_dimensions_invalid", "活动图片尺寸必须为 1280×960");
                return;
            }
            stream.Seek(segmentLength - 2, SeekOrigin.Current);
        }
        throw InvalidImage();
    }

    private static byte ReadByte(BinaryReader reader)
    {
        try { return reader.ReadByte(); }
        catch (EndOfStreamException) { throw InvalidImage(); }
    }

    private static ushort ReadUInt16BigEndian(BinaryReader reader) =>
        (ushort)((ReadByte(reader) << 8) | ReadByte(reader));

    private static ApiException InvalidImage() =>
        new(400, "cover_content_invalid", "图片内容不是有效 JPEG");
}
