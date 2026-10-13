# frozen_string_literal: true

class GratitudeDetector
  GRATITUDE_PATTERNS = [
    # English gratitude & closing expressions
    /\b(thank\s*you|thanks|thx|appreciate\s*it|grateful|great\s*job|awesome|perfect|all\s*good|all\s*set)\b/i,
    /\b(issue\s*is\s*resolved|works\s*now|fixed\s*now|have\s*a\s*great\s*day|cheers)\b/i,
    # Turkish gratitude & closing expressions
    /\b(teşekkür|tesekkur|teşekkürler|tesekkurler|sağol|sagol|sağolun|sagolun|harikasınız|harikasiniz)\b/i,
    /\b(ellerinize\s*sağlık|ellerinize\s*saglik|çok\s*sağolun|cok\s*sagolun|sorun\s*çözüldü|sorun\s*cozuldu|düzeldi|duzeldi)\b/i,
    # Automated Out-of-Office / Vacation patterns
    /\b(out\s*of\s*office|automatic\s*reply|auto\s*reply|autoreply|on\s*vacation|away\s*from\s*office)\b/i,
    /\b(otomatik\s*yanıt|otomatik\s*cevap|ofis\s*dışındayım|tatildeyim|izinliyim)\b/i
  ].freeze

  REOPEN_OVERRIDE_PATTERNS = [
    /\b(not\s*working|still\s*broken|still\s*an\s*issue|didn't\s*work|did\s*not\s*work|error|failed|wait|help)\b/i,
    /\b(çalışmıyor|calismiyor|hâlâ\s*hata|hala\s*hata|olmadı|olmadi|sorun\s*devam|düzelmedi|duzelmedi|çözülmedi|cozulmedi)\b/i
  ].freeze

  def self.gratitude_or_out_of_office?(text)
    return false if text.blank?

    cleaned = text.strip

    # If the user expresses that something is still broken, do NOT treat as mere gratitude
    return false if REOPEN_OVERRIDE_PATTERNS.any? { |pattern| cleaned.match?(pattern) }

    # If it matches any gratitude or out-of-office pattern
    GRATITUDE_PATTERNS.any? { |pattern| cleaned.match?(pattern) }
  end
end
