class FeedbackEligibilityData {
  const FeedbackEligibilityData({
    required this.eligible,
    this.likeTag,
    this.reportTag,
  });

  final bool eligible;
  final String? likeTag;
  final String? reportTag;

  factory FeedbackEligibilityData.fromJson(Map<String, dynamic>? json) =>
      FeedbackEligibilityData(
        eligible: json?['eligible'] == true,
        likeTag: json?['likeTag'] as String?,
        reportTag: json?['reportTag'] as String?,
      );

  FeedbackEligibilityData copyWith({String? likeTag, String? reportTag}) =>
      FeedbackEligibilityData(
        eligible: eligible,
        likeTag: likeTag ?? this.likeTag,
        reportTag: reportTag ?? this.reportTag,
      );
}

const activityLikeTags = [
  'punctual',
  'newcomer_friendly',
  'well_organized',
  'clear_communication',
  'welcoming',
  'safe_respectful',
  'good_value',
  'would_join_again',
];

const userLikeTags = [
  'punctual',
  'friendly',
  'communicative',
  'respectful',
  'helpful',
  'positive',
  'reliable',
  'would_meet_again',
];

const activityReportTags = [
  'misleading_information',
  'organizer_no_show',
  'unsafe_arrangement',
  'inappropriate_behavior',
  'unexpected_costs',
  'privacy_issue',
  'spam_commercial',
  'discrimination',
];

const userReportTags = [
  'no_show',
  'harassment',
  'inappropriate_content',
  'unsafe_behavior',
  'dishonesty',
  'spam',
  'discrimination',
  'privacy_violation',
];
