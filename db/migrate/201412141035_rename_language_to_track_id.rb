class RenameLanguageToTrackId < ActiveRecord::Migration
  def change
    rename_column :submissions, :language, :track_id
    rename_column :user_exercises, :language, :track_id
  end
end
