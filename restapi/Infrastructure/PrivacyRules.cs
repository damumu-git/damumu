namespace Muda.Api.Infrastructure;

public static class PrivacyRules
{
    public const string NoticeVersion = "2026-10-21";
    public const int MinimumAge = 14;

    public static void ValidateRegistration(bool ageConfirmed, bool noticeAcknowledged, string? version)
    {
        if (!ageConfirmed)
            throw new ApiException(400, "minimum_age_confirmation_required", "请确认已满14周岁");
        if (!noticeAcknowledged || version != NoticeVersion)
            throw new ApiException(400, "privacy_notice_required", "请阅读并确认当前隐私政策");
    }
}
