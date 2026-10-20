import '../sync_core.dart';

String taskRepeatLabel(TaskRepeatRule? rule) {
  if (rule == null) {
    return '不重复';
  }
  final count = rule.interval == 1 ? '' : '${rule.interval} ';
  return switch (rule.frequency) {
    'daily' => '每$count天',
    'weekly' =>
      '每$count周${rule.weekdays.isEmpty ? '' : ' · ${rule.weekdays.map((day) => ['一', '二', '三', '四', '五', '六', '日'][day.clamp(1, 7).toInt() - 1]).join('、')}'}',
    'monthly' =>
      '每$count月${rule.monthDay == null ? '' : ' · ${rule.monthDay} 日'}',
    _ => '重复待办',
  };
}
