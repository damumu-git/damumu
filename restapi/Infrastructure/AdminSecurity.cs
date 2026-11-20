using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.DataProtection;

namespace Muda.Api.Infrastructure;

public sealed class AdminSecurity(Db db, AuthService auth, IDataProtectionProvider protection)
{
    private readonly IDataProtector protector = protection.CreateProtector("damumu.admin.totp.v1");

    public async Task<Dictionary<string, object?>?> CurrentAsync(HttpContext context, CancellationToken ct)
    {
        var token = context.Request.Cookies[SessionSecurity.AdminCookie];
        if (token is null || token.Length > 256) return null;
        return await db.QueryOneAsync("""
            SELECT a.id,a.username,a.role FROM admin_session s JOIN admin_account a ON a.id=s.admin_id
            WHERE token_hash=@hash AND expires_at>now() AND a.enabled
            """, new { hash = SessionSecurity.Hash(token) }, ct);
    }

    public async Task LoginAsync(HttpContext context, string? username, string? password, string? code, CancellationToken ct)
    {
        if (username?.Length is not (> 0 and <= 80) || password?.Length is not (> 0 and <= 256) || code?.Length != 6)
            throw new ApiException(401, "admin_login_failed", "账号、密码或验证码不正确");
        var security = context.RequestServices.GetRequiredService<SessionSecurity>();
        var bucket = "admin:" + username.Trim().ToLowerInvariant();
        await security.CheckAttemptAsync(bucket, ct);
        var account = await db.QueryOneAsync("SELECT * FROM admin_account WHERE username=@username AND enabled",
            new { username = username.Trim().ToLowerInvariant() }, ct);
        // Spend comparable password work for unknown accounts.
        var passwordValid = account is null ? auth.VerifyPassword(password, DummyPasswordHash) :
            auth.VerifyPassword(password, (string)account["password_hash"]!);
        long step = -1;
        if (passwordValid && account is not null)
        {
            var secret = protector.Unprotect((string)account["totp_secret"]!);
            step = VerifyTotp(secret, code);
        }
        if (account is null || !passwordValid || step < 0)
        {
            await security.FailedAttemptAsync(bucket, ct);
            throw new ApiException(401, "admin_login_failed", "账号、密码或验证码不正确");
        }
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        var result = await db.QueryOneAsync("""
            WITH verified AS (
                UPDATE admin_account SET last_totp_step=@step WHERE id=@id AND last_totp_step<@step RETURNING id
            )
            INSERT INTO admin_session(token_hash,admin_id,expires_at)
            SELECT @hash,id,now()+interval '2 hours' FROM verified RETURNING admin_id
            """, new { id = account["id"], step, hash = SessionSecurity.Hash(token) }, ct);
        if (result is null) throw new ApiException(401, "admin_login_failed", "验证码已使用，请等待下一个验证码");
        context.Response.Cookies.Append(SessionSecurity.AdminCookie, token, SessionSecurity.Cookie());
        await db.ExecuteAsync("""
            INSERT INTO audit_log(admin_account_id,actor_role,action,target_type,metadata)
            VALUES(@id,'admin','admin.login','admin_account','{}')
            """, new { id = account["id"] }, ct);
    }

    private const string DummyPasswordHash =
        "pbkdf2-sha256$600000$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    public async Task BootstrapAsync(string username, string role, CancellationToken ct)
    {
        if (username.Length is < 3 or > 80 || role is not ("owner" or "moderator" or "viewer"))
            throw new InvalidOperationException("Use --create-admin <username> [owner|moderator|viewer].");
        Console.Write("New administrator password (at least 14 characters): ");
        var password = new StringBuilder();
        for (ConsoleKeyInfo key; (key = Console.ReadKey(true)).Key != ConsoleKey.Enter;)
        {
            if (key.Key == ConsoleKey.Backspace) { if (password.Length > 0) password.Length--; }
            else if (!char.IsControl(key.KeyChar)) password.Append(key.KeyChar);
        }
        Console.WriteLine();
        if (password.Length is < 14 or > 256) throw new InvalidOperationException("Password must contain 14 to 256 characters.");
        var secret = Base32(RandomNumberGenerator.GetBytes(20));
        var usernameKey = username.Trim().ToLowerInvariant();
        await db.ExecuteAsync("""
            INSERT INTO admin_account(username,password_hash,totp_secret,role) VALUES(@username,@password,@secret,@role)
            """, new { username = usernameKey, password = auth.HashPassword(password.ToString()), secret = protector.Protect(secret), role }, ct);
        Console.WriteLine("Add this account to your authenticator and store its setup key securely:");
        Console.WriteLine($"otpauth://totp/DAMUMU:{Uri.EscapeDataString(usernameKey)}?secret={secret}&issuer=DAMUMU");
        Console.WriteLine("One-time setup key: " + secret);
    }

    public static long VerifyTotp(string secret, string code)
    {
        if (code.Length != 6 || code.Any(c => c is < '0' or > '9')) return -1;
        var key = DecodeBase32(secret);
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds() / 30;
        for (var step = now - 1; step <= now + 1; step++)
        {
            var counter = new byte[8];
            BinaryPrimitives.WriteInt64BigEndian(counter, step);
            var hash = HMACSHA1.HashData(key, counter);
            var offset = hash[^1] & 15;
            var number = (BinaryPrimitives.ReadInt32BigEndian(hash.AsSpan(offset, 4)) & 0x7fffffff) % 1000000;
            if (CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(code),
                Encoding.ASCII.GetBytes(number.ToString("D6")))) return step;
        }
        return -1;
    }

    private static string Base32(byte[] bytes)
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        var result = new StringBuilder();
        var buffer = 0;
        var bits = 0;
        foreach (var value in bytes)
        {
            buffer = (buffer << 8) | value;
            bits += 8;
            while (bits >= 5) { bits -= 5; result.Append(alphabet[(buffer >> bits) & 31]); }
        }
        if (bits > 0) result.Append(alphabet[(buffer << (5 - bits)) & 31]);
        return result.ToString();
    }

    private static byte[] DecodeBase32(string text)
    {
        var result = new List<byte>();
        var buffer = 0;
        var bits = 0;
        foreach (var c in text)
        {
            var value = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".IndexOf(c);
            if (value < 0) throw new FormatException("Invalid authenticator secret.");
            buffer = (buffer << 5) | value;
            bits += 5;
            if (bits >= 8) { bits -= 8; result.Add((byte)(buffer >> bits)); }
        }
        return result.ToArray();
    }
}
