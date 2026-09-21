using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;

namespace Muda.Api.Infrastructure;

public sealed class PushNotificationService
{
    private readonly FirebaseMessaging? _messaging;
    private readonly ILogger<PushNotificationService> _logger;

    public PushNotificationService(IConfiguration configuration, ILogger<PushNotificationService> logger)
    {
        _logger = logger;
        var projectId = configuration["Firebase:ProjectId"];
        if (string.IsNullOrWhiteSpace(projectId))
        {
            logger.LogInformation("Firebase push is disabled because Firebase:ProjectId is not configured");
            return;
        }

        try
        {
            var app = FirebaseApp.Create(new AppOptions
            {
                Credential = GoogleCredential.GetApplicationDefault(),
                ProjectId = projectId
            }, "damumu-push");
            _messaging = FirebaseMessaging.GetMessaging(app);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Firebase push initialization failed; realtime and stored notifications remain available");
        }
    }

    public bool IsConfigured => _messaging is not null;

    public async Task SendToUsersAsync(
        Db db,
        IEnumerable<Guid> userIds,
        string title,
        string body,
        IReadOnlyDictionary<string, string> data,
        CancellationToken cancellationToken = default)
    {
        if (_messaging is null) return;
        var ids = userIds.Distinct().ToArray();
        if (ids.Length == 0) return;

        var devices = await db.QueryAsync(
            """
            SELECT id, registration_token
            FROM push_device
            WHERE user_id=ANY(@userIds) AND enabled=true
            """, new { userIds = ids }, cancellationToken);
        if (devices.Count == 0) return;

#pragma warning disable CS0618
        var messages = devices.Select(device => new Message
        {
            Token = (string)device["registration_token"]!,
            Notification = new Notification { Title = title, Body = body },
            Data = new Dictionary<string, string>(data)
        }).ToList();
#pragma warning restore CS0618

        try
        {
            var response = await _messaging.SendEachAsync(messages, cancellationToken);
            if (response.FailureCount > 0)
                _logger.LogWarning(
                    "FCM delivered {SuccessCount} messages and failed {FailureCount}",
                    response.SuccessCount,
                    response.FailureCount);
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "FCM delivery failed; clients will synchronize stored notifications later");
        }
    }
}
