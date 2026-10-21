using System.Data;
using Npgsql;

namespace Muda.Api.Infrastructure;

public sealed class AccountDeletionService(
    NpgsqlDataSource dataSource,
    MediaStorage media,
    ILogger<AccountDeletionService> logger)
{
    public async Task<AccountDeletionResult?> DeleteAsync(
        Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable, cancellationToken);

        await using (var findUser = new NpgsqlCommand(
            """
            SELECT 1
            FROM app_user u
            WHERE u.id=@userId AND u.deleted_at IS NULL
            FOR UPDATE OF u
            """, connection, transaction))
        {
            findUser.Parameters.AddWithValue("userId", userId);
            await using var reader = await findUser.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) return null;
        }

        await using (var deleteAccount = new NpgsqlCommand(
            """
            UPDATE event
            SET status='cancelled',
                cancelled_at=COALESCE(cancelled_at, now()),
                cancellation_reason=COALESCE(cancellation_reason, '组织者已注销账号'),
                updated_at=now()
            WHERE organizer_user_id=@userId
              AND deleted_at IS NULL
              AND status NOT IN ('cancelled', 'completed')
              AND EXISTS (
                  SELECT 1 FROM event_schedule es
                  WHERE es.event_id=event.id AND es.ends_at >= now()
              );

            UPDATE event_member
            SET application_note=NULL, share_contact=false, updated_at=now()
            WHERE user_id=@userId;

            UPDATE event SET reviewed_by_user_id=NULL WHERE reviewed_by_user_id=@userId;
            UPDATE event_member SET reviewed_by_user_id=NULL WHERE reviewed_by_user_id=@userId;
            UPDATE place SET created_by_user_id=NULL WHERE created_by_user_id=@userId;
            UPDATE media_asset SET owner_user_id=NULL, updated_at=now() WHERE owner_user_id=@userId;
            UPDATE report SET reported_user_id=NULL WHERE reported_user_id=@userId;
            UPDATE report SET assigned_to_user_id=NULL WHERE assigned_to_user_id=@userId;
            UPDATE moderation_action SET moderator_user_id=NULL WHERE moderator_user_id=@userId;
            UPDATE app_config SET updated_by_user_id=NULL WHERE updated_by_user_id=@userId;
            UPDATE feature_flag SET updated_by_user_id=NULL WHERE updated_by_user_id=@userId;
            UPDATE audit_log SET actor_user_id=NULL WHERE actor_user_id=@userId;

            INSERT INTO media_deletion_queue(storage_key,is_directory)
            VALUES ('avatars/' || replace(CAST(@userId AS text),'-',''),true)
            ON CONFLICT (storage_key) DO UPDATE SET is_directory=true;

            DELETE FROM push_device WHERE user_id=@userId;
            DELETE FROM user_credential WHERE user_id=@userId;
            DELETE FROM notification WHERE user_id=@userId;
            DELETE FROM conversation_member WHERE user_id=@userId;
            DELETE FROM user_block WHERE blocker_user_id=@userId OR blocked_user_id=@userId;
            DELETE FROM user_interest WHERE user_id=@userId;
            DELETE FROM trust_snapshot WHERE user_id=@userId;
            DELETE FROM review WHERE from_user_id=@userId OR to_user_id=@userId;
            DELETE FROM endorsement WHERE from_user_id=@userId OR target_user_id=@userId;
            DELETE FROM safety_session WHERE user_id=@userId;
            DELETE FROM emergency_contact WHERE user_id=@userId;

            UPDATE user_profile
            SET nickname='注销用户_' || nextval('muda_deleted_user_number'),
                avatar_url=NULL,
                bio=NULL,
                city_code=NULL,
                district_code=NULL,
                languages=ARRAY[]::varchar[],
                gender=NULL,
                occupation=NULL,
                arrival_year=NULL,
                profile_completed_at=NULL,
                contact_type=NULL,
                contact_value=NULL,
                updated_at=now()
            WHERE user_id=@userId;

            UPDATE app_user
            SET status='deleted',
                locale='und',
                timezone='UTC',
                adult_confirmed_at=NULL,
                minimum_age_confirmed_at=NULL,
                privacy_notice_version=NULL,
                privacy_notice_acknowledged_at=NULL,
                last_login_at=NULL,
                deletion_requested_at=COALESCE(deletion_requested_at, now()),
                deleted_at=now(),
                updated_at=now()
            WHERE id=@userId;
            """, connection, transaction))
        {
            deleteAccount.Parameters.AddWithValue("userId", userId);
            await deleteAccount.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        var avatarFilesDeleted = DeleteAvatarFiles(userId);
        return new AccountDeletionResult(DateTimeOffset.UtcNow, avatarFilesDeleted);
    }

    private bool DeleteAvatarFiles(Guid userId)
    {
        var avatarRoot = media.GetPath("avatars");
        var userDirectory = Path.GetFullPath(Path.Combine(avatarRoot, userId.ToString("N")));
        if (!userDirectory.StartsWith(
                avatarRoot + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase))
            return false;
        try
        {
            if (Directory.Exists(userDirectory)) Directory.Delete(userDirectory, recursive: true);
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            logger.LogCritical(
                exception,
                "Account {UserId} was anonymized but its avatar directory requires manual cleanup",
                userId);
            return false;
        }
    }
}

public sealed record AccountDeletionResult(DateTimeOffset DeletedAt, bool AvatarFilesDeleted);
