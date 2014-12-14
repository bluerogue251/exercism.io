class Homework
  attr_reader :user
  def initialize(user)
    @user = user
  end

  def all
    sql = "SELECT track_id, slug, state FROM user_exercises WHERE user_id = #{user.id} ORDER BY track_id, slug ASC"
    extract(sql)
  end

  private

  def extract(sql)
    exercises = Hash.new {|exercises, key| exercises[key] = []}
    UserExercise.connection.execute(sql).each_with_object(exercises) {|row, exercises|
      exercises[row['track_id']] << {"slug" => row["slug"], "state" => row["state"]}
    }
  end
end
