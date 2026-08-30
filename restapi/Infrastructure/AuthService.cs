using System.Security.Cryptography;
using System.Text;

namespace Muda.Api.Infrastructure;

public sealed class AuthService(IConfiguration configuration)
{
    private const int Iterations = 120_000;
    private readonly byte[] _tokenKey = Encoding.UTF8.GetBytes(
        configuration["Auth:TokenKey"]
        ?? throw new InvalidOperationException("Auth:TokenKey is required."));

    public string HashPassword(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(
            password, salt, Iterations, HashAlgorithmName.SHA256, 32);
        return $"pbkdf2-sha256${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    public bool VerifyPassword(string password, string encoded)
    {
        var parts = encoded.Split('$');
        if (parts.Length != 4 || parts[0] != "pbkdf2-sha256"
            || !int.TryParse(parts[1], out var iterations)) return false;
        try
        {
            var salt = Convert.FromBase64String(parts[2]);
            var expected = Convert.FromBase64String(parts[3]);
            var actual = Rfc2898DeriveBytes.Pbkdf2(
                password, salt, iterations, HashAlgorithmName.SHA256, expected.Length);
            return CryptographicOperations.FixedTimeEquals(actual, expected);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    public string CreateToken(Guid userId)
    {
        var expiresAt = DateTimeOffset.UtcNow.AddDays(30).ToUnixTimeSeconds();
        var payload = $"{userId:N}.{expiresAt}";
        var signature = HMACSHA256.HashData(_tokenKey, Encoding.UTF8.GetBytes(payload));
        return $"{payload}.{Base64Url(signature)}";
    }

    public bool TryValidateToken(string token, out Guid userId)
    {
        userId = default;
        var pieces = token.Split('.');
        if (pieces.Length != 3) return false;
        try
        {
            var payload = $"{pieces[0]}.{pieces[1]}";
            var supplied = FromBase64Url(pieces[2]);
            var expected = HMACSHA256.HashData(_tokenKey, Encoding.UTF8.GetBytes(payload));
            return CryptographicOperations.FixedTimeEquals(supplied, expected)
                && Guid.TryParseExact(pieces[0], "N", out userId)
                && long.TryParse(pieces[1], out var expiresAt)
                && expiresAt > DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static string Base64Url(string value) =>
        Base64Url(Encoding.UTF8.GetBytes(value));

    private static string Base64Url(byte[] value) =>
        Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] FromBase64Url(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded += new string('=', (4 - padded.Length % 4) % 4);
        return Convert.FromBase64String(padded);
    }
}
