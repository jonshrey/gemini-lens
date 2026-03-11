class AgentIntent {
  final String intent;
  final String summary;
  final Map<String, dynamic> actionData;

  AgentIntent({
    required this.intent,
    required this.summary,
    required this.actionData,
  });

  factory AgentIntent.fromJson(Map<String, dynamic> json) {
    return AgentIntent(
      intent: json['intent'] ?? 'general_info',
      summary: json['summary'] ?? 'I could not determine what to do.',
      actionData: json['actionData'] ?? {},
    );
  }
}