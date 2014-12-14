module TemporaryLanguageToTrackIdTranslator
  def language=(track_id)
    self.track_id = track_id
  end

  def language
    track_id
  end
end
